const fs = require("fs");
const runElm = require("./compile-elm.js");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { elmPagesCliFile, elmPagesUiFile } = require("./elm-file-constants.js");
const path = require("path");
const { ensureDirSync, deleteIfExists } = require('./file-helpers.js')
let wasEqualBefore = false


module.exports = function run(
  mode,
  staticRoutes,
  markdownContent
) {
  ensureDirSync("./elm-stuff");
  ensureDirSync("./elm-stuff/elm-pages");

  // prevent compilation errors if migrating from previous elm-pages version
  deleteIfExists("./elm-stuff/elm-pages/Pages/ContentCache.elm");
  deleteIfExists("./elm-stuff/elm-pages/Pages/Platform.elm");


  const uiFileContent = elmPagesUiFile(staticRoutes, markdownContent)

  // TODO should just write it once, but webpack doesn't seem to pick up the changes
  // so this wasEqualBefore code causes it to get written twice to make sure the changes come through for HMR
  if (wasEqualBefore) {
    fs.writeFileSync(
      "./gen/Pages.elm",
      uiFileContent
    );
  }
  if (global.previousUiFileContent === uiFileContent) {
    wasEqualBefore = false
  } else {
    wasEqualBefore = true
    fs.writeFileSync(
      "./gen/Pages.elm",
      uiFileContent
    );
  }

  global.previousUiFileContent = uiFileContent

  // write `Pages.elm` with cli interface
  fs.writeFileSync(
    "./elm-stuff/elm-pages/Pages.elm",
    elmPagesCliFile(staticRoutes, markdownContent)
  );

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();

  // run Main.elm from elm-stuff/elm-pages with `runElm`
  return runElm(mode);
};
