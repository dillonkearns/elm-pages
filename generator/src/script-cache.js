import * as fs from "node:fs";
import * as path from "node:path";
import * as globby from "globby";
import { packageVersion } from "./compatibility-key.js";

const VERSION_MARKER_FILE = ".elm-pages-cli-version";

/**
 * Check if the stored elm-pages version matches the current version.
 * @param {string} projectDirectory - The project directory
 * @returns {Promise<boolean>} - Returns true if versions match, false otherwise
 */
async function checkVersionMatch(projectDirectory) {
  const versionPath = path.join(
    projectDirectory,
    "elm-stuff/elm-pages",
    VERSION_MARKER_FILE
  );
  try {
    const storedVersion = (await fs.promises.readFile(versionPath, "utf8")).trim();
    return storedVersion === packageVersion;
  } catch (e) {
    // Version file doesn't exist
    return false;
  }
}

/**
 * Write the current elm-pages version to the marker file.
 * @param {string} projectDirectory - The project directory
 */
export async function updateVersionMarker(projectDirectory) {
  const versionPath = path.join(
    projectDirectory,
    "elm-stuff/elm-pages",
    VERSION_MARKER_FILE
  );
  const versionDir = path.dirname(versionPath);
  await fs.promises.mkdir(versionDir, { recursive: true });
  await fs.promises.writeFile(versionPath, packageVersion);
}

/**
 * Check if recompilation is needed by comparing output mtime against source files.
 * @param {string} projectDirectory - The project directory
 * @param {string} outputPath - Path to the compiled output file (e.g., elm.cjs)
 * @returns {Promise<boolean>} - Returns true if recompilation is needed
 */
export async function needsRecompilation(projectDirectory, outputPath) {
  try {
    // Check if elm-pages version has changed
    const versionMatch = await checkVersionMatch(projectDirectory);
    if (!versionMatch) {
      return true;
    }

    const outputStat = await fs.promises.stat(outputPath);
    const outputMtime = outputStat.mtimeMs;

    // Read elm.json to get source-directories
    const elmJsonPath = path.join(projectDirectory, "elm.json");
    const elmJson = JSON.parse(await fs.promises.readFile(elmJsonPath, "utf8"));
    const sourceDirectories = elmJson["source-directories"] || ["."];

    // Check elm.json itself
    const elmJsonStat = await fs.promises.stat(elmJsonPath);
    if (elmJsonStat.mtimeMs > outputMtime) {
      return true;
    }

    // Check all .elm files in source directories
    for (const srcDir of sourceDirectories) {
      const fullSrcDir = path.join(projectDirectory, srcDir);
      const elmFiles = globby.globbySync(`${fullSrcDir}/**/*.elm`);

      for (const elmFile of elmFiles) {
        try {
          const fileStat = await fs.promises.stat(elmFile);
          if (fileStat.mtimeMs > outputMtime) {
            return true;
          }
        } catch (e) {
          // File might have been deleted, consider it changed
          return true;
        }
      }
    }

    // Also check the generated ScriptMain.elm
    const scriptMainPath = path.join(
      projectDirectory,
      "elm-stuff/elm-pages/.elm-pages/ScriptMain.elm"
    );
    try {
      const scriptMainStat = await fs.promises.stat(scriptMainPath);
      if (scriptMainStat.mtimeMs > outputMtime) {
        return true;
      }
    } catch (e) {
      // ScriptMain doesn't exist, needs compilation
      return true;
    }

    // Also check the elm-stuff/elm-pages/elm.json (the rewritten one)
    const rewrittenElmJsonPath = path.join(
      projectDirectory,
      "elm-stuff/elm-pages/elm.json"
    );
    try {
      const rewrittenElmJsonStat = await fs.promises.stat(rewrittenElmJsonPath);
      if (rewrittenElmJsonStat.mtimeMs > outputMtime) {
        return true;
      }
    } catch (e) {
      // Rewritten elm.json doesn't exist, needs compilation
      return true;
    }

    // Check files in parentDirectory (copied .elm files from project root)
    const parentDirPath = path.join(
      projectDirectory,
      "elm-stuff/elm-pages/parentDirectory"
    );
    try {
      const parentDirFiles = await fs.promises.readdir(parentDirPath);
      for (const file of parentDirFiles) {
        if (file.endsWith(".elm")) {
          const filePath = path.join(parentDirPath, file);
          const fileStat = await fs.promises.stat(filePath);
          if (fileStat.mtimeMs > outputMtime) {
            return true;
          }
        }
      }
    } catch (e) {
      // parentDirectory doesn't exist, needs compilation
      return true;
    }

    // Output is up-to-date
    return false;
  } catch (e) {
    // Output doesn't exist or other error
    return true;
  }
}

/**
 * Check if elm-codegen install needs to run by comparing marker file against codegen sources.
 * @param {string} projectDirectory - The project directory
 * @returns {Promise<boolean>} - Returns true if elm-codegen install is needed
 */
export async function needsCodegenInstall(projectDirectory) {
  const codegenDir = path.join(projectDirectory, "codegen");
  const markerPath = path.join(
    projectDirectory,
    "elm-stuff/elm-pages/.codegen-install-marker"
  );

  try {
    // Check if codegen directory exists
    await fs.promises.access(codegenDir, fs.constants.F_OK);
  } catch (e) {
    // No codegen directory, no install needed
    return false;
  }

  try {
    const markerStat = await fs.promises.stat(markerPath);
    const markerMtime = markerStat.mtimeMs;

    // Check all files in codegen directory
    const codegenFiles = globby.globbySync(`${codegenDir}/**/*`);

    for (const file of codegenFiles) {
      try {
        const fileStat = await fs.promises.stat(file);
        if (fileStat.mtimeMs > markerMtime) {
          return true;
        }
      } catch (e) {
        // File issue, run install to be safe
        return true;
      }
    }

    // Marker is up-to-date
    return false;
  } catch (e) {
    // Marker doesn't exist, needs install
    return true;
  }
}

/**
 * Update the codegen install marker file.
 * @param {string} projectDirectory - The project directory
 */
export async function updateCodegenMarker(projectDirectory) {
  const markerPath = path.join(
    projectDirectory,
    "elm-stuff/elm-pages/.codegen-install-marker"
  );

  // Ensure directory exists
  const markerDir = path.dirname(markerPath);
  await fs.promises.mkdir(markerDir, { recursive: true });

  // Touch the marker file
  const now = new Date();
  try {
    await fs.promises.utimes(markerPath, now, now);
  } catch (e) {
    // File doesn't exist, create it
    await fs.promises.writeFile(markerPath, "");
  }
}

/**
 * Check if custom-backend-task needs recompilation.
 * @param {string} projectDirectory - The project directory
 * @returns {Promise<{needed: boolean, outputPath: string | null}>}
 */
export async function needsPortsRecompilation(projectDirectory) {
  const outputPath = path.join(
    projectDirectory,
    ".elm-pages/compiled-ports/custom-backend-task.mjs"
  );

  // Find custom-backend-task source files
  const sourceFiles = globby.globbySync(
    path.join(projectDirectory, "custom-backend-task.*")
  );

  // No source files means no compilation needed
  if (sourceFiles.length === 0) {
    return { needed: false, outputPath: null };
  }

  try {
    const outputStat = await fs.promises.stat(outputPath);
    const outputMtime = outputStat.mtimeMs;

    // Check if any source file is newer than output
    for (const sourceFile of sourceFiles) {
      const sourceStat = await fs.promises.stat(sourceFile);
      if (sourceStat.mtimeMs > outputMtime) {
        return { needed: true, outputPath };
      }
    }

    // Output is up-to-date
    return { needed: false, outputPath };
  } catch (e) {
    // Output doesn't exist, needs compilation
    return { needed: true, outputPath };
  }
}
