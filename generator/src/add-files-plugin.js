const path = require("path");

module.exports = class AddFilesPlugin {
  constructor(filesList) {
    this.filesList = filesList;
  }
  apply(compiler) {
    compiler.hooks.afterCompile.tap("AddFilesPlugin", compilation => {
      this.filesList.forEach(file => {
        // Couldn't find this documented in the webpack docs,
        // but I found the example code for it here:
        // https://github.com/jantimon/html-webpack-plugin/blob/35a154186501fba3ecddb819b6f632556d37a58f/index.js#L470-L478

        const filename = path.join(file.name, "content.txt");
        compilation.fileDependencies.add(filename);
        compilation.assets[filename] = {
          source: () => file.content,
          size: () => file.content.length
        };
      });
    });
  }
};
