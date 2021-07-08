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
  ensureDirSync("./.elm-pages");
  ensureDirSync("./elm-stuff/elm-pages/.elm-pages");

  fs.copyFileSync(path.join(__dirname, `./Page.elm`), `./.elm-pages/Page.elm`);
  fs.copyFileSync(
    path.join(__dirname, `./elm-application.json`),
    `./elm-stuff/elm-pages/elm-application.json`
  );
  fs.copyFileSync(
    path.join(__dirname, `./Page.elm`),
    `./elm-stuff/elm-pages/.elm-pages/Page.elm`
  );
  fs.copyFileSync(
    path.join(__dirname, `./SharedTemplate.elm`),
    `./.elm-pages/SharedTemplate.elm`
  );
  fs.copyFileSync(
    path.join(__dirname, `./SharedTemplate.elm`),
    `./elm-stuff/elm-pages/.elm-pages/SharedTemplate.elm`
  );
  fs.copyFileSync(
    path.join(__dirname, `./SiteConfig.elm`),
    `./.elm-pages/SiteConfig.elm`
  );
  fs.copyFileSync(
    path.join(__dirname, `./SiteConfig.elm`),
    `./elm-stuff/elm-pages/.elm-pages/SiteConfig.elm`
  );

  const uiFileContent = elmPagesUiFile();
  fs.writeFileSync("./.elm-pages/Pages.elm", uiFileContent);

  // write `Pages.elm` with cli interface
  fs.writeFileSync(
    "./elm-stuff/elm-pages/.elm-pages/Pages.elm",
    elmPagesCliFile()
  );
  fs.writeFileSync(
    "./elm-stuff/elm-pages/.elm-pages/TemplateModulesBeta.elm",
    cliCode.mainModule
  );
  fs.writeFileSync(
    "./elm-stuff/elm-pages/.elm-pages/Route.elm",
    cliCode.routesModule
  );
  fs.writeFileSync(
    "./.elm-pages/TemplateModulesBeta.elm",
    browserCode.mainModule
  );
  fs.writeFileSync("./.elm-pages/Route.elm", browserCode.routesModule);

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();
}

module.exports = { generate };
