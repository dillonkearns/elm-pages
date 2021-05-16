const fs = require("fs");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { elmPagesCliFile, elmPagesUiFile } = require("./elm-file-constants.js");
const {
  generateTemplateModuleConnector,
} = require("./generate-template-module-connector.js");
const path = require("path");
const { ensureDirSync, deleteIfExists } = require("./file-helpers.js");
global.builtAt = new Date();

async function generate() {
  await writeFiles();
}

async function writeFiles() {
  const cliCode = generateTemplateModuleConnector("cli");
  const browserCode = generateTemplateModuleConnector("browser");
  ensureDirSync("./elm-stuff");
  ensureDirSync("./gen");
  ensureDirSync("./elm-stuff/elm-pages");
  fs.copyFileSync(path.join(__dirname, `./Page.elm`), `./gen/Page.elm`);
  fs.copyFileSync(
    path.join(__dirname, `./Page.elm`),
    `./elm-stuff/elm-pages/Page.elm`
  );
  fs.copyFileSync(
    path.join(__dirname, `./SharedTemplate.elm`),
    `./gen/SharedTemplate.elm`
  );
  fs.copyFileSync(
    path.join(__dirname, `./SharedTemplate.elm`),
    `./elm-stuff/elm-pages/SharedTemplate.elm`
  );

  // prevent compilation errors if migrating from previous elm-pages version
  deleteIfExists("./elm-stuff/elm-pages/Pages/ContentCache.elm");
  deleteIfExists("./elm-stuff/elm-pages/Pages/Platform.elm");

  const uiFileContent = elmPagesUiFile();
  fs.writeFileSync("./gen/Pages.elm", uiFileContent);

  // write `Pages.elm` with cli interface
  fs.writeFileSync("./elm-stuff/elm-pages/Pages.elm", elmPagesCliFile());
  fs.writeFileSync(
    "./elm-stuff/elm-pages/TemplateModulesBeta.elm",
    cliCode.mainModule
  );
  fs.writeFileSync("./elm-stuff/elm-pages/Route.elm", cliCode.routesModule);
  fs.writeFileSync("./gen/TemplateModulesBeta.elm", browserCode.mainModule);
  fs.writeFileSync("./gen/Route.elm", browserCode.routesModule);

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();
}

module.exports = { generate };
