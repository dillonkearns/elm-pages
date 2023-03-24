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
  // ./elm-stuff/elm-pages/
  // So, we need to take the existing elmJson and
  // 1. remove existing path that looks at `Pages.elm`
  elmJson["source-directories"] = elmJson["source-directories"].filter(
    (item) => {
      return item != ".elm-pages";
    }
  );
  // 2. prepend ../../../ to remaining
  elmJson["source-directories"] = elmJson["source-directories"].map((item) => {
    return "../../" + item;
  });
  if (options && options.executableName === "elm") {
    // elm, don't add lamdera/codecs
  } else {
    // lamdera, add codecs dependency
    elmJson["dependencies"]["direct"]["lamdera/codecs"] = "1.0.0";
  }
  // 3. add our own secret My.elm module 😈
  elmJson["source-directories"].push(".elm-pages");
  return elmJson;
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
