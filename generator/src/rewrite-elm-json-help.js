import * as fs from "node:fs";
import * as path from "node:path";

/**
 * @param {string} sourceElmJsonPath
 * @param {string} targetElmJsonPath
 * @param {( (arg0: JSON) => JSON )?} modifyElmJson
 */
export async function rewriteElmJson(
  sourceElmJsonPath,
  targetElmJsonPath,
  modifyElmJson
) {
  if (!modifyElmJson) {
    modifyElmJson = function (json) {
      return json;
    };
  }
  var elmJson = JSON.parse(
    (
      await fs.promises.readFile(path.join(sourceElmJsonPath, "elm.json"))
    ).toString()
  );

  let modifiedElmJson = modifyElmJson(elmJson);
  // always add `lamdera/codecs` dependency
  modifiedElmJson["dependencies"]["direct"]["lamdera/codecs"] = "1.0.0";

  // write new elm.json
  await writeFileIfChanged(
    path.join(targetElmJsonPath, "elm.json"),
    JSON.stringify(modifiedElmJson)
  );
}

/**
 * @param {fs.PathLike | fs.promises.FileHandle} filePath
 * @param {string | NodeJS.ArrayBufferView | Iterable<string | NodeJS.ArrayBufferView> | AsyncIterable<string | NodeJS.ArrayBufferView> | import("stream").Stream} content
 */
async function writeFileIfChanged(filePath, content) {
  if (
    !(await fileExists(filePath)) ||
    (await fs.promises.readFile(filePath, "utf8")) !== content
  ) {
    await fs.promises.writeFile(filePath, content);
  }
}
/**
 * @param {fs.PathLike} file
 */
function fileExists(file) {
  return fs.promises
    .access(file, fs.constants.F_OK)
    .then(() => true)
    .catch(() => false);
}
