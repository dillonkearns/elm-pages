const path = require("path");
const fs = require("fs");
const glob = require("glob");
const parseFrontmatter = require("./frontmatter.js");

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
    content
  };
}

module.exports = class AddFilesPlugin {
  constructor() {}
  apply(compiler) {
    compiler.hooks.emit.tap("AddFilesPlugin", compilation => {
      const files = glob.sync("content/**/*.*", {}).map(unpackFile);

      files.forEach(file => {
        // Couldn't find this documented in the webpack docs,
        // but I found the example code for it here:
        // https://github.com/jantimon/html-webpack-plugin/blob/35a154186501fba3ecddb819b6f632556d37a58f/index.js#L470-L478

        const filename = path.join(file.baseRoute, "content.json");
        compilation.fileDependencies.add(filename);
        const rawContents = JSON.stringify({
          body: file.content,
          staticData: { stargazers_count: 85 }
        });

        compilation.assets[filename] = {
          source: () => rawContents,
          size: () => rawContents.length
        };
      });
    });
  }
};
