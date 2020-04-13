const path = require("path");
const fs = require("fs");
const globby = require("globby");
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
  constructor(data, filesToGenerate) {
    this.pagesWithRequests = data;
    this.filesToGenerate = filesToGenerate;
  }
  apply(compiler) {
    compiler.hooks.afterCompile.tap("AddFilesPlugin", compilation => {
      const files = globby
        .sync(["content/**/*.*", "!content/**/*.emu"], {})
        .map(unpackFile);

      compilation.contextDependencies.add(path.resolve('./content'));
      files.forEach(file => {
        // Couldn't find this documented in the webpack docs,
        // but I found the example code for it here:
        // https://github.com/jantimon/html-webpack-plugin/blob/35a154186501fba3ecddb819b6f632556d37a58f/index.js#L470-L478

        let route = file.baseRoute.replace(/\/$/, '');
        const staticRequests = this.pagesWithRequests[route];

        const filename = path.join(file.baseRoute, "content.json");
        compilation.fileDependencies.add(filename);
        const rawContents = JSON.stringify({
          body: file.content,
          staticData: staticRequests || {}
        });

        compilation.assets[filename] = {
          source: () => rawContents,
          size: () => rawContents.length
        };
      });

      (this.filesToGenerate || []).forEach(file => {
        // Couldn't find this documented in the webpack docs,
        // but I found the example code for it here:
        // https://github.com/jantimon/html-webpack-plugin/blob/35a154186501fba3ecddb819b6f632556d37a58f/index.js#L470-L478
        compilation.assets[file.path] = {
          source: () => file.content,
          size: () => file.content.length
        };
      });


    });
  }
};
