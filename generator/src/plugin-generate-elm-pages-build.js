const fs = require('fs')
const path = require('path')
const doCliStuff = require("./generate-elm-stuff.js");
const webpack = require('webpack')
const parseFrontmatter = require("./frontmatter.js");
const generateRecords = require("./generate-records.js");
const globby = require("globby");

module.exports = class PluginGenerateElmPagesBuild {
    constructor() {
        this.value = 1;
    }

    apply(/** @type {webpack.Compiler} */ compiler) {
        compiler.hooks.afterEmit.tap('DoneMsg', () => {
            console.log('---> DONE!');

        })

        compiler.hooks.beforeCompile.tap('PluginGenerateElmPagesBuild', (compilation) => {
            // compiler.hooks.thisCompilation.tap('PluginGenerateElmPagesBuild', (compilation) => {

            // compilation.contextDependencies.add('content')
            // compiler.hooks.thisCompilation.tap('ThisCompilation', (compilation) => {
            console.log('----> PluginGenerateElmPagesBuild');
            const src = `module Example exposing (..)

value : Int
value = ${this.value++}
`
            // console.log('@@@ Writing EXAMPLE module');
            // fs.writeFileSync(path.join(process.cwd(), './src/Example.elm'), src);

            const staticRoutes = generateRecords();

            const markdownContent = globby
                .sync(["content/**/*.*"], {})
                .map(unpackFile)
                .map(({ path, contents }) => {
                    return parseMarkdown(path, contents);
                });

            const images = globby
                .sync("images/**/*", {})
                .filter(imagePath => !fs.lstatSync(imagePath).isDirectory());

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
                console.log('PROMISE RESOLVED doCliStuff');


                resolvePageRequests(payload);
                global.filesToGenerate = payload.filesToGenerate;

            }).catch(function (errorPayload) {
                resolvePageRequests({ type: 'error', message: errorPayload });
            })


            // compilation.assets['./src/Example.elm'] = {
            //     source: () => src,
            //     size: () => src.length
            // };
            // callback()

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
        extension: "md"
    };
}