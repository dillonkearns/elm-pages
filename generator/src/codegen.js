const fs = require("fs");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { elmPagesCliFile, elmPagesUiFile } = require("./elm-file-constants.js");
const {
  generateTemplateModuleConnector,
} = require("./generate-template-module-connector.js");
const path = require("path");
const { ensureDirSync, deleteIfExists } = require("./file-helpers.js");
global.builtAt = new Date();

/**
 * @param {string} basePath
 */
async function generate(basePath) {
  const cliCode = generateTemplateModuleConnector(basePath, "cli");
  const browserCode = generateTemplateModuleConnector(basePath, "browser");
  ensureDirSync("./elm-stuff");
  ensureDirSync("./.elm-pages");
  ensureDirSync("./elm-stuff/elm-pages/.elm-pages");

  const uiFileContent = elmPagesUiFile();
  await Promise.all([
    fs.promises.copyFile(
      path.join(__dirname, `./Page.elm`),
      `./.elm-pages/Page.elm`
    ),
    fs.promises.copyFile(
      path.join(__dirname, `./elm-application.json`),
      `./elm-stuff/elm-pages/elm-application.json`
    ),
    fs.promises.copyFile(
      path.join(__dirname, `./Page.elm`),
      `./elm-stuff/elm-pages/.elm-pages/Page.elm`
    ),
    fs.promises.copyFile(
      path.join(__dirname, `./SharedTemplate.elm`),
      `./.elm-pages/SharedTemplate.elm`
    ),
    fs.promises.copyFile(
      path.join(__dirname, `./SharedTemplate.elm`),
      `./elm-stuff/elm-pages/.elm-pages/SharedTemplate.elm`
    ),
    fs.promises.copyFile(
      path.join(__dirname, `./SiteConfig.elm`),
      `./.elm-pages/SiteConfig.elm`
    ),
    fs.promises.copyFile(
      path.join(__dirname, `./SiteConfig.elm`),
      `./elm-stuff/elm-pages/.elm-pages/SiteConfig.elm`
    ),
    fs.promises.writeFile("./.elm-pages/Pages.elm", uiFileContent),
    // write `Pages.elm` with cli interface
    fs.promises.writeFile(
      "./elm-stuff/elm-pages/.elm-pages/Pages.elm",
      elmPagesCliFile()
    ),
    fs.promises.writeFile(
      "./elm-stuff/elm-pages/.elm-pages/TemplateModulesBeta.elm",
      cliCode.mainModule
    ),
    fs.promises.writeFile(
      "./elm-stuff/elm-pages/.elm-pages/Route.elm",
      cliCode.routesModule
    ),
    fs.promises.writeFile(
      "./.elm-pages/TemplateModulesBeta.elm",
      browserCode.mainModule
    ),
    fs.promises.writeFile("./.elm-pages/Route.elm", browserCode.routesModule),
  ]);

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();
}

module.exports = { generate };
