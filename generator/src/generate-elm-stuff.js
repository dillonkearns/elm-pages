const fs = require("fs");
const runElm = require("./compile-elm.js");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { elmPagesCliFile } = require("./elm-file-constants.js");

module.exports = function run(
  staticRoutes,
  markdownContent,
  markupContent,
  callback
) {
  // mkdir -p elm-stuff/elm-pages/
  // requires NodeJS >= 10.12.0
  fs.mkdirSync("./elm-stuff/elm-pages", { recursive: true });

  // write `Pages.elm` with cli interface
  fs.writeFileSync(
    "./elm-stuff/elm-pages/Pages.elm",
    elmPagesCliFile(staticRoutes, markdownContent, markupContent)
  );

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();

  // run Main.elm from elm-stuff/elm-pages with `runElm`
  runElm(callback);
};
