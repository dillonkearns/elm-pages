import * as fs from "node:fs";

export async function rewriteClientElmJson(options = {}) {
  var elmJson = JSON.parse(
    (await fs.promises.readFile("./elm.json")).toString()
  );

  // write new elm.json

  await writeFileIfChanged(
    "./elm-stuff/elm-pages/client/elm.json",
    JSON.stringify(rewriteClientElmJsonHelp(elmJson, options))
  );
}

function rewriteClientElmJsonHelp(elmJson, options = {}) {
  const localSourceDirectories = options.localSourceDirectories || null;

  // The internal generated file will be at:
  // ./elm-stuff/elm-pages/
  // So, we need to take the existing elmJson and
  // 1. remove existing path that looks at `Pages.elm`
  elmJson["source-directories"] = elmJson["source-directories"].filter(
    (item) => {
      if (item == ".elm-pages") {
        return false;
      }

      if (!localSourceDirectories && item == "app") {
        return false;
      }

      return true;
    }
  );
  // 2. prepend ../../../ to remaining
  elmJson["source-directories"] = elmJson["source-directories"].map((item) => {
    if (
      localSourceDirectories &&
      Object.prototype.hasOwnProperty.call(localSourceDirectories, item)
    ) {
      return localSourceDirectories[item];
    }
    return "../../../" + item;
  });
  elmJson["dependencies"]["direct"]["lamdera/codecs"] = "1.0.0";
  // 3. add our own secret My.elm module 😈
  elmJson["source-directories"].push(".elm-pages");
  if (!localSourceDirectories) {
    elmJson["source-directories"].push("app");
  }
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
