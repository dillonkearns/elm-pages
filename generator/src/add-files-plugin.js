const path = require("path");
const fs = require("fs");
const globby = require("globby");
const parseFrontmatter = require("./frontmatter.js");
const webpack = require('webpack')

function unpackFile(filePath) {
  const { content, data } = parseFrontmatter(
    filePath,
    fs.readFileSync(filePath).toString()
  );

  const baseRoute = filePath
    .replace("content/", "")
    .replace(/(index)?\.[a-zA-Z]*$/, "");

  return {
    baseRoute,
    content,
    filePath
  };
}

module.exports = class AddFilesPlugin {
  constructor(data, filesToGenerate) {
    this.pagesWithRequests = data;
    this.filesToGenerate = filesToGenerate;
  }
  apply(/** @type {webpack.Compiler} */ compiler) {
    compiler.hooks.afterCompile.tapAsync("AddFilesPlugin", (compilation, callback) => {
      const files = globby
        .sync(["content/**/*.*"], {})
        .map(unpackFile);

      global.pagesWithRequests.then(pageWithRequests => {
        files.forEach(file => {
          // Couldn't find this documented in the webpack docs,
          // but I found the example code for it here:
          // https://github.com/jantimon/html-webpack-plugin/blob/35a154186501fba3ecddb819b6f632556d37a58f/index.js#L470-L478

          let route = file.baseRoute.replace(/\/$/, '');
          const staticRequests = pageWithRequests[route];

          const filename = path.join(file.baseRoute, "content.json");
          // compilation.fileDependencies.add(filename);
          compilation.fileDependencies.add(path.resolve(file.filePath));
          const rawContents = JSON.stringify({
            body: file.content,
            staticData: staticRequests || {}
          });

          compilation.assets[filename] = {
            source: () => rawContents,
            size: () => rawContents.length
          };
        });

        (global.filesToGenerate || []).forEach(file => {
          // Couldn't find this documented in the webpack docs,
          // but I found the example code for it here:
          // https://github.com/jantimon/html-webpack-plugin/blob/35a154186501fba3ecddb819b6f632556d37a58f/index.js#L470-L478
          compilation.assets[file.path] = {
            source: () => file.content,
            size: () => file.content.length
          };
        });

        callback()
      }).catch(errorPayload => {

        compilation.errors.push(new Error(errorPayload))
        callback()
      })
    });
  }
};
