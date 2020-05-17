const fs = require('fs')
const path = require('path')
const doCliStuff = require("./generate-elm-stuff.js");
const webpack = require('webpack')
const parseFrontmatter = require("./frontmatter.js");
const generateRecords = require("./generate-records.js");
const globby = require("globby");

module.exports = class PluginGenerateElmPagesBuild {
    constructor() {
    }

    apply(/** @type {webpack.Compiler} */ compiler) {
        compiler.hooks.beforeCompile.tapAsync('PluginGenerateElmPagesBuild', (compilation, done) => {
            const staticRoutes = generateRecords();

            const markdownContent = globby
                .sync(["content/**/*.*"], {})
                .map(unpackFile)
                .map(({ path, contents }) => {
                    return parseMarkdown(path, contents);
                });

            let resolvePageRequests;
            let rejectPageRequests;
            global.pagesWithRequests = new Promise(function (resolve, reject) {
                resolvePageRequests = resolve;
                rejectPageRequests = reject;
            });

            doCliStuff(
                global.mode,
                staticRoutes,
                markdownContent
            ).then((payload) => {
                // console.log('PROMISE RESOLVED doCliStuff');

                resolvePageRequests(payload);
                global.filesToGenerate = payload.filesToGenerate;
                done()

            }).catch(function (errorPayload) {
                resolvePageRequests({ type: 'error', message: errorPayload });
                done()
            })

        });
    };

}


function unpackFile(path) {
    return { path, contents: fs.readFileSync(path).toString() };
}

function parseMarkdown(path, fileContents) {
    const { content, data } = parseFrontmatter(path, fileContents);
    return {
        path,
        metadata: JSON.stringify(data),
        body: content,
    };
}