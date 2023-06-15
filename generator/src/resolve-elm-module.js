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

function downloadRemoteScript({ remote, owner, repo, branch }) {
  return new Promise(async (resolve, reject) => {
    branch ||= "master";
    const cloneToPath = path.join(
      "elm-stuff",
      "elm-pages",
      "remote-scripts",
      owner,
      repo
    );

    const repoExists = fs.existsSync(cloneToPath);

    let subprocess;
    if (repoExists) {
      subprocess = spawn("git", ["pull"], {
        cwd: cloneToPath,
      });
    } else {
      subprocess = spawn("git", ["clone", "--depth=1", remote, cloneToPath], {
        cwd: process.cwd(),
      });
    }

    let commandOutput = "";

    subprocess.stderr.on("data", function (data) {
      commandOutput += data;
    });

    subprocess.on("close", async (code) => {
      if (code === 0) {
        resolve(cloneToPath);
      } else {
        process.exitCode = 1;
        reject(`I encountered an error cloning the repo:\n\n ${commandOutput}`);
      }
    });
  });
}
