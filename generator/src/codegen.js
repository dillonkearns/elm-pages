const fs = require("fs");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { elmPagesCliFile, elmPagesUiFile } = require("./elm-file-constants.js");
const {
  generateTemplateModuleConnector,
} = require("./generate-template-module-connector.js");
const path = require("path");
const { ensureDirSync, deleteIfExists } = require("./file-helpers.js");
const generateRecords = require("./generate-records.js");

async function generate() {
  global.builtAt = new Date();
  global.staticHttpCache = {};

  await writeFiles();
}

async function writeFiles() {
  const staticRoutes = await generateRecords();
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

  const uiFileContent = elmPagesUiFile(staticRoutes);
  fs.writeFileSync("./gen/Pages.elm", uiFileContent);

  // write `Pages.elm` with cli interface
  fs.writeFileSync(
    "./elm-stuff/elm-pages/Pages.elm",
    elmPagesCliFile(staticRoutes)
  );
  fs.writeFileSync(
    "./elm-stuff/elm-pages/TemplateModulesBeta.elm",
    generateTemplateModuleConnector("cli")
  );
  fs.writeFileSync(
    "./gen/TemplateModulesBeta.elm",
    generateTemplateModuleConnector("browser")
  );

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();
}

module.exports = { generate };
