import * as fs from "node:fs";
import * as path from "node:path";
import { spawn } from "cross-spawn";
import { parse } from "../src/parse-remote.js";

function findNearestElmJson(filePath) {
  function searchForElmJson(directory) {
    if (directory === "/") {
      return null;
    }

    const elmJsonPath = path.join(directory, "elm.json");
    return fs.existsSync(elmJsonPath)
      ? elmJsonPath
      : searchForElmJson(path.dirname(directory));
  }

  return searchForElmJson(path.dirname(filePath));
}

function getElmModuleName(inputPath) {
  const filePath = path.normalize(
    path.isAbsolute(inputPath) ? inputPath : path.resolve(inputPath)
  );
  const elmJsonPath = findNearestElmJson(filePath);

  if (!elmJsonPath) {
    throw new Error("No elm.json found");
  }

  const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
  const sourceDirectories = elmJson["source-directories"];
  const projectDirectory = path.dirname(elmJsonPath);

  const matchingSourceDir = sourceDirectories
    .map((sourceDir) => path.join(projectDirectory, sourceDir))
    .find((absoluteSourceDir) => filePath.startsWith(absoluteSourceDir));

  if (!matchingSourceDir) {
    throw new Error(
      "File is not in any source-directories specified in elm.json"
    );
  }

  const relativePath = path.relative(matchingSourceDir, filePath);
  const moduleName = relativePath
    .replace(path.extname(relativePath), "")
    .replace("/", ".");

  return { projectDirectory, moduleName, sourceDirectory: matchingSourceDir };
}

export async function resolveInputPathOrModuleName(inputPathOrModuleName) {
  const parsed = parse(inputPathOrModuleName);
  if (parsed) {
    const { filePath } = parsed;
    const repoPath = await downloadRemoteScript(parsed);
    const absolutePathForScript = path.join(repoPath, filePath);
    return getElmModuleName(absolutePathForScript);
  } else if (
    /^[A-Z][a-zA-Z0-9_]*(\.[A-Z][a-zA-Z0-9_]*)*$/.test(inputPathOrModuleName)
  ) {
    const absolutePathForScript = path.resolve("./script/src");
    return {
      moduleName: inputPathOrModuleName,
      projectDirectory: path.resolve("./script"),
      sourceDirectory: path.resolve("./script/src"),
    };
  } else {
    return getElmModuleName(inputPathOrModuleName);
  }
}

/**
 * Parse the remote script TTL from environment variables.
 * Returns TTL in seconds, or Infinity for offline mode, or 0 for always fetch.
 */
function getRemoteScriptTTL() {
  const ttlValue = process.env.ELM_PAGES_REMOTE_SCRIPT_TTL;

  if (ttlValue === undefined) {
    return 0; // Default: always fetch
  }

  // Check for "infinity" variants (offline mode)
  const lowerValue = ttlValue.toLowerCase();
  if (lowerValue === "infinity" || lowerValue === "inf" || lowerValue === "offline" || lowerValue === "never") {
    return Infinity;
  }

  const parsed = parseInt(ttlValue, 10);
  if (isNaN(parsed)) {
    return 0; // Invalid value, default to always fetch
  }

  // -1 also means infinity (common convention)
  if (parsed < 0) {
    return Infinity;
  }

  return parsed;
}

/**
 * Check if we need to fetch based on TTL and last fetch time.
 * Uses git's FETCH_HEAD mtime as the last fetch timestamp.
 */
function shouldFetch(cloneToPath, ttlSeconds) {
  if (ttlSeconds === 0) {
    return true; // Always fetch
  }

  if (ttlSeconds === Infinity) {
    return false; // Never fetch (offline mode)
  }

  const fetchHeadPath = path.join(cloneToPath, ".git", "FETCH_HEAD");
  try {
    const stats = fs.statSync(fetchHeadPath);
    const lastFetchMs = stats.mtimeMs;
    const nowMs = Date.now();
    const ageSeconds = (nowMs - lastFetchMs) / 1000;
    return ageSeconds > ttlSeconds;
  } catch (e) {
    // FETCH_HEAD doesn't exist (never fetched), so we should fetch
    return true;
  }
}

async function downloadRemoteScript({ remote, owner, repo, branch }) {
  try {
    const cloneToPath = path.join(
      "elm-stuff",
      "elm-pages",
      "remote-scripts",
      owner,
      repo
    );

    const repoExists = fs.existsSync(cloneToPath);
    const ttlSeconds = getRemoteScriptTTL();
    const needsFetch = repoExists ? shouldFetch(cloneToPath, ttlSeconds) : true;

    if (!needsFetch && repoExists) {
      // Within TTL: skip git fetch, use cached repo as-is
      // Just ensure we're on the right branch if specified
      if (branch) {
        const currentBranch = (await exec("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
          cwd: cloneToPath,
        })).trim();
        if (currentBranch !== branch) {
          // Try to checkout the branch (must already exist locally)
          await exec("git", ["checkout", branch], {
            cwd: cloneToPath,
          });
        }
      }
      return cloneToPath;
    }

    if (ttlSeconds === Infinity && !repoExists) {
      throw `Offline mode is enabled (ELM_PAGES_REMOTE_SCRIPT_TTL=infinity) but the remote script has not been cached yet.\nRun once without the TTL setting to cache the script first.`;
    }

    if (repoExists) {
      if (branch) {
        // Branch is specified in URL - just fetch and checkout that branch
        // No need for `git remote show origin` to get default branch
        await exec("git", ["fetch", "origin", branch], {
          cwd: cloneToPath,
        });
        // Use reset --hard to handle shallow clone and ensure we're at origin's state
        await exec("git", ["checkout", branch], {
          cwd: cloneToPath,
        }).catch(async () => {
          // Branch doesn't exist locally yet, create it tracking origin
          await exec("git", ["checkout", "-b", branch, `origin/${branch}`], {
            cwd: cloneToPath,
          });
        });
        await exec("git", ["reset", "--hard", `origin/${branch}`], {
          cwd: cloneToPath,
        });
      } else {
        // No branch specified - use current branch and just pull latest
        const currentBranch = (await exec("git", ["rev-parse", "--abbrev-ref", "HEAD"], {
          cwd: cloneToPath,
        })).trim();
        await exec("git", ["fetch", "origin", currentBranch], { cwd: cloneToPath });
        await exec("git", ["reset", "--hard", `origin/${currentBranch}`], {
          cwd: cloneToPath,
        });
      }
    } else {
      if (branch) {
        await exec("git", [
          "clone",
          "--branch",
          branch,
          "--depth=1",
          remote,
          cloneToPath,
        ]);
      } else {
        await exec("git", ["clone", "--depth=1", remote, cloneToPath]);
      }
    }
    return cloneToPath;
  } catch (error) {
    process.exitCode = 1;
    throw `I encountered an error cloning the repo:\n\n ${error}`;
  }
}

/**
 * @param {string} command
 * @param {readonly string[]} args
 * @param {import("child_process").SpawnOptionsWithoutStdio} [ options ]
 */
function exec(command, args, options) {
  return new Promise(async (resolve, reject) => {
    let subprocess = spawn(command, args, options);
    let commandOutput = "";

    subprocess.stderr.on("data", function (data) {
      commandOutput += data;
    });

    subprocess.stdout.on("data", function (data) {
      commandOutput += data;
    });

    subprocess.on("close", async (code) => {
      if (code === 0) {
        resolve(commandOutput);
      } else {
        reject(commandOutput);
      }
    });
  });
}
