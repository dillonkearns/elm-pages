const {
  elmPagesCliFile,
  elmPagesUiFile,
} = require("../generator/src/elm-file-constants.js");
const {
  generateTemplateModuleConnector,
} = require("../generator/src/generate-template-module-connector.js");
const generateRecords = require("../generator/src/generate-records.js");

test("generate UI file", async () => {
  process.chdir(__dirname);
  const staticRoutes = await generateRecords();

  global.builtAt = new Date("Sun, 17 May 2020 16:53:22 GMT");
  expect(elmPagesUiFile(staticRoutes, [])).toMatchSnapshot();
});

test("generate template module connector", async () => {
  process.chdir(__dirname);
  const generated = await generateTemplateModuleConnector();

  expect(generated).toMatchSnapshot();
});
