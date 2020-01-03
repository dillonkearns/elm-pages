const fs = require("fs");
const runElm = require("./compile-elm.js");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { elmPagesCliFile } = require("./elm-file-constants.js");
const path = require("path");
const { ensureDirSync, deleteIfExists } = require('./file-helpers.js')


module.exports = function run(
  mode,
  staticRoutes,
  markdownContent,
  markupContent,
  callback
) {
  ensureDirSync("./elm-stuff");
  ensureDirSync("./elm-stuff/elm-pages");

  // prevent compilation errors if migrating from previous elm-pages version
  deleteIfExists("./elm-stuff/elm-pages/Pages/ContentCache.elm");
  deleteIfExists("./elm-stuff/elm-pages/Pages/Platform.elm");
  

  // write `Pages.elm` with cli interface
  fs.writeFileSync(
    "./elm-stuff/elm-pages/Pages.elm",
    elmPagesCliFile(staticRoutes, markdownContent, markupContent)
  );

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();

  // run Main.elm from elm-stuff/elm-pages with `runElm`
  runElm(mode, callback);
};
