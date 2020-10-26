const fs = require("fs");
const copyModifiedElmJson = require("./rewrite-elm-json.js");
const { elmPagesCliFile, elmPagesUiFile } = require("./elm-file-constants.js");
const {
  generateTemplateModuleConnector,
} = require("./generate-template-module-connector.js");
const path = require("path");
const { ensureDirSync, deleteIfExists } = require("./file-helpers.js");
const globby = require("globby");
const parseFrontmatter = require("./frontmatter.js");
const generateRecords = require("./generate-records.js");

async function generate() {
  global.builtAt = new Date();
  global.staticHttpCache = {};

  const markdownContent = globby
    .sync(["content/**/*.*"], {})
    .map(unpackFile)
    .map(({ path, contents }) => {
      return parseMarkdown(path, contents);
    });
  const routes = toRoutes(markdownContent);
  await writeFiles(markdownContent);
}

function unpackFile(path) {
  return { path, contents: fs.readFileSync(path).toString() };
}

function toRoutes(entries) {
  return entries.map(toRoute);
}

function toRoute(entry) {
  let fullPath = entry.path
    .replace(/(index)?\.[^/.]+$/, "")
    .split("/")
    .filter((item) => item !== "")
    .slice(1);

  return fullPath.join("/");
}

async function writeFiles(markdownContent) {
  const staticRoutes = await generateRecords();
  ensureDirSync("./elm-stuff");
  ensureDirSync("./gen");
  ensureDirSync("./elm-stuff/elm-pages");

  // prevent compilation errors if migrating from previous elm-pages version
  deleteIfExists("./elm-stuff/elm-pages/Pages/ContentCache.elm");
  deleteIfExists("./elm-stuff/elm-pages/Pages/Platform.elm");

  const uiFileContent = elmPagesUiFile(staticRoutes, markdownContent);
  const templateConnectorFile = generateTemplateModuleConnector();

  fs.writeFileSync("./gen/Pages.elm", uiFileContent);

  // write `Pages.elm` with cli interface
  fs.writeFileSync(
    "./elm-stuff/elm-pages/Pages.elm",
    elmPagesCliFile(staticRoutes, markdownContent)
  );
  fs.writeFileSync(
    "./elm-stuff/elm-pages/TemplateModulesBeta.elm",
    templateConnectorFile
  );
  fs.writeFileSync("./gen/TemplateModulesBeta.elm", templateConnectorFile);

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();
}

function parseMarkdown(path, fileContents) {
  const { content, data } = parseFrontmatter(path, fileContents);
  return {
    path,
    metadata: JSON.stringify(data),
    body: content,
  };
}

module.exports = { generate };
