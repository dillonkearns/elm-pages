const path = require("path");
const matter = require("gray-matter");

module.exports = function parseFrontmatter(filePath, fileContents) {
  return path.extname(filePath) === ".emu"
    ? matter(fileContents, markupFrontmatterOptions)
    : matter(fileContents);
};

const markupFrontmatterOptions = {
  language: "markup",
  engines: {
    markup: {
      parse: function(string) {
        return string;
      },

      stringify: function(string) {
        return string;
      }
    }
  }
};
