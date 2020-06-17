const { elmPagesCliFile, elmPagesUiFile } = require("../../../generator/src/elm-file-constants.js");
const generateRecords = require("../../../generator/src/generate-records.js");

test('casing is correct for directories', async () => {
    process.chdir(__dirname);
    const staticRoutes = await generateRecords();

    global.builtAt = new Date("Sun, 17 May 2020 16:53:22 GMT");
    expect(elmPagesUiFile(staticRoutes, [])).toMatchSnapshot();
});
