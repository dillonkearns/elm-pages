const { elmPagesCliFile, elmPagesUiFile } = require("../generator/src/elm-file-constants.js");
const generateRecords = require("../generator/src/generate-records.js");
const path = require('path');

const { readdirSync } = require('fs');
global.builtAt = new Date("Sun, 17 May 2020 16:53:22 GMT");

const getDirectories = (/** @type {string} */ source) =>
    readdirSync(source, { withFileTypes: true })
        .filter(dirent => dirent.isDirectory())
        .map(dirent => dirent.name)

getDirectories(path.join(__dirname, 'snapshot-cases')).forEach(snapshotDir => {

    test(`generate UI file ${snapshotDir}`, async () => {
        process.chdir(path.join(__dirname, 'snapshot-cases', snapshotDir));
        const staticRoutes = await generateRecords();
        expect(elmPagesUiFile(staticRoutes, [])).toMatchSnapshot();
    });


})
