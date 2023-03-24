import * as fs from "node:fs";
import * as path from "node:path";

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

export function resolveInputPathOrModuleName(inputPathOrModuleName) {
  if (
    /^[A-Z][a-zA-Z0-9_]*(\.[A-Z][a-zA-Z0-9_]*)*$/.test(inputPathOrModuleName)
  ) {
    return {
      moduleName: inputPathOrModuleName,
      projectDirectory: "./script",
      sourceDirectory: "./script/src",
    };
  } else {
    return getElmModuleName(inputPathOrModuleName);
  }
}
