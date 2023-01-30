import * as fs from "node:fs";

export async function rewriteClientElmJson() {
  var elmJson = JSON.parse(
    (await fs.promises.readFile("./elm.json")).toString()
  );

  // write new elm.json

  await writeFileIfChanged(
    "./elm-stuff/elm-pages/client/elm.json",
    JSON.stringify(rewriteClientElmJsonHelp(elmJson))
  );
}

function rewriteClientElmJsonHelp(elmJson) {
  // The internal generated file will be at:
  // ./elm-stuff/elm-pages/
  // So, we need to take the existing elmJson and
  // 1. remove existing path that looks at `Pages.elm`
  elmJson["source-directories"] = elmJson["source-directories"].filter(
    (item) => {
      return item != ".elm-pages" && item != "app";
    }
  );
  // 2. prepend ../../../ to remaining
  elmJson["source-directories"] = elmJson["source-directories"].map((item) => {
    return "../../../" + item;
  });
  // 3. add our own secret My.elm module 😈
  elmJson["source-directories"].push(".elm-pages");
  elmJson["source-directories"].push("app");
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
