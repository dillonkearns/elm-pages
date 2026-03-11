import * as fs from "node:fs";

export async function rewriteElmJson(
  sourceElmJsonPath,
  targetElmJsonPath,
  options
) {
  var elmJson = JSON.parse(
    (await fs.promises.readFile(sourceElmJsonPath)).toString()
  );

  // write new elm.json

  await writeFileIfChanged(
    targetElmJsonPath,
    JSON.stringify(rewriteElmJsonHelp(elmJson, options))
  );
}

function rewriteElmJsonHelp(elmJson, options) {
  // The internal generated file will be at:
  // ./elm-stuff/elm-pages/ (depth 2) or ./elm-stuff/elm-pages/server/ (depth 3)
  // So, we need to take the existing elmJson and
  // 1. remove existing path that looks at `Pages.elm`
  elmJson["source-directories"] = elmJson["source-directories"].filter(
    (item) => {
      return item != ".elm-pages";
    }
  );
  // 2. prepend appropriate number of ../ to remaining
  // Default depth is 2 (for elm-stuff/elm-pages/), but can be overridden
  const pathPrefix = options && options.pathPrefix ? options.pathPrefix : "../../";

  // For server folder, keep `app/` local instead of pointing to parent
  // because we copy app files to the server folder for transformation
  const keepAppLocal = options && options.keepAppLocal;

  elmJson["source-directories"] = elmJson["source-directories"].map((item) => {
    if (item === ".") {
      return "parentDirectory";
    } else if (keepAppLocal && item === "app") {
      // Keep app local for server folder - files are copied and transformed there
      return "app";
    } else {
      return pathPrefix + item;
    }
  });
  addDirectDependency(elmJson, "lamdera/codecs", "1.0.0");
  addDirectDependency(elmJson, "elm/bytes", "1.0.8");
  addDirectDependency(elmJson, "dillonkearns/elm-ts-json", "2.1.1");
  addIndirectDependency(elmJson, "elm-community/dict-extra", "2.4.0");
  // 3. add our own secret My.elm module 😈
  elmJson["source-directories"].push(".elm-pages");
  return elmJson;
}

function addDirectDependency(elmJson, pkg, version) {
  elmJson["dependencies"]["direct"][pkg] = version;
  delete elmJson["dependencies"]["indirect"][pkg];
}

function addIndirectDependency(elmJson, pkg, version) {
  if (!elmJson["dependencies"]["direct"][pkg]) {
    elmJson["dependencies"]["indirect"][pkg] = version;
  }
}

async function writeFileIfChanged(filePath, content) {
  if (
    !(await fileExists(filePath)) ||
    (await fs.promises.readFile(filePath, "utf8")) !== content
  ) {
    await fs.promises.writeFile(filePath, content);
  }
}
function fileExists(file) {
  return fs.promises
    .access(file, fs.constants.F_OK)
    .then(() => true)
    .catch(() => false);
}
