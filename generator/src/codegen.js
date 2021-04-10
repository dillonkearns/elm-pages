const fs = require("fs");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { elmPagesCliFile, elmPagesUiFile } = require("./elm-file-constants.js");
const {
  generateTemplateModuleConnector,
} = require("./generate-template-module-connector.js");
const path = require("path");
const { ensureDirSync, deleteIfExists } = require("./file-helpers.js");

async function generate() {
  global.builtAt = new Date();
  global.staticHttpCache = {};

  await writeFiles();
}

async function writeFiles() {
  ensureDirSync("./elm-stuff");
  ensureDirSync("./gen");
  ensureDirSync("./elm-stuff/elm-pages");
  fs.copyFileSync(path.join(__dirname, `./Template.elm`), `./gen/Template.elm`);
  fs.copyFileSync(
    path.join(__dirname, `./Template.elm`),
    `./elm-stuff/elm-pages/Template.elm`
  );

  // prevent compilation errors if migrating from previous elm-pages version
  deleteIfExists("./elm-stuff/elm-pages/Pages/ContentCache.elm");
  deleteIfExists("./elm-stuff/elm-pages/Pages/Platform.elm");

  const uiFileContent = elmPagesUiFile();
  fs.writeFileSync("./gen/Pages.elm", uiFileContent);

  // write `Pages.elm` with cli interface
  fs.writeFileSync("./elm-stuff/elm-pages/Pages.elm", elmPagesCliFile());
  const cliCode = generateTemplateModuleConnector("cli");
  fs.writeFileSync(
    "./elm-stuff/elm-pages/TemplateModulesBeta.elm",
    cliCode.mainModule
  );
  const browserCode = generateTemplateModuleConnector("browser");
  fs.writeFileSync("./gen/TemplateModulesBeta.elm", browserCode.mainModule);

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();
}

module.exports = { generate };
