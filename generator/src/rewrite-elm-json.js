const fs = require("fs");

module.exports = function () {
  var elmJson = JSON.parse(fs.readFileSync("./elm.json").toString());

  // write new elm.json
  fs.writeFileSync(
    "./elm-stuff/elm-pages/elm.json",
    JSON.stringify(rewriteElmJson(elmJson))
  );
};

function rewriteElmJson(elmJson) {
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
  // 3. add our own secret My.elm module 😈
  elmJson["source-directories"].push(".elm-pages");
  return elmJson;
}
