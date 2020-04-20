const path = require("path");
const matter = require("gray-matter");

module.exports = function parseFrontmatter(filePath, fileContents) {
  return matter(fileContents);
};
