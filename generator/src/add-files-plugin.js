const path = require("path");
const fs = require("fs");
const globby = require("globby");
const parseFrontmatter = require("./frontmatter.js");
const webpack = require("webpack");

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
    filePath,
  };
}

module.exports = class AddFilesPlugin {
  apply(/** @type {webpack.Compiler} */ compiler) {
    (global.mode === "dev"
      ? compiler.hooks.emit
      : compiler.hooks.make
    ).tapAsync("AddFilesPlugin", (compilation, callback) => {
      const files = globby.sync("content").map(unpackFile);

      let staticRequestData = {};
      global.pagesWithRequests
        .then((payload) => {
          if (payload.type === "error") {
            compilation.errors.push(new Error(payload.message));
          } else if (payload.errors && payload.errors.length > 0) {
            compilation.errors.push(new Error(payload.errors[0]));
          } else {
            staticRequestData = payload.pages;
          }
        })
        .finally(() => {
          files.forEach((file) => {
            // Couldn't find this documented in the webpack docs,
            // but I found the example code for it here:
            // https://github.com/jantimon/html-webpack-plugin/blob/35a154186501fba3ecddb819b6f632556d37a58f/index.js#L470-L478

            let route = file.baseRoute.replace(/\/$/, "");
            const staticRequests = staticRequestData[route];

            const filename = path.join(file.baseRoute, "content.json");
            if (compilation.contextDependencies) {
              compilation.contextDependencies.add("content");
            }
            // compilation.fileDependencies.add(filename);
            if (compilation.fileDependencies) {
              compilation.fileDependencies.add(path.resolve(file.filePath));
            }
            const rawContents = JSON.stringify({
              body: file.content,
              staticData: staticRequests || {},
            });

            compilation.assets[filename] = {
              source: () => rawContents,
              size: () => rawContents.length,
            };
          });

          (global.filesToGenerate || []).forEach((file) => {
            // Couldn't find this documented in the webpack docs,
            // but I found the example code for it here:
            // https://github.com/jantimon/html-webpack-plugin/blob/35a154186501fba3ecddb819b6f632556d37a58f/index.js#L470-L478
            compilation.assets[file.path] = {
              source: () => file.content,
              size: () => file.content.length,
            };
          });

          callback();
        });
    });
  }
};
