const util = require("util");
const fsSync = require("fs");
const fs = {
  writeFile: util.promisify(fsSync.writeFile),
  mkdir: util.promisify(fsSync.mkdir),
  readFile: util.promisify(fsSync.readFile),
  copyFile: util.promisify(fsSync.copyFile),
  exists: util.promisify(fsSync.exists),
  readdir: util.promisify(fsSync.readdir),
};

/**
 * @param {import("fs").PathLike} dirName
 */
async function tryMkdir(dirName) {
  const exists = await fs.exists(dirName);
  if (!exists) {
    fs.mkdir(dirName, { recursive: true });
  }
}

const path = require("path");

/**
 * @param {string} srcDirectory
 * @param {string} destDir
 */
async function copyDirFlat(srcDirectory, destDir) {
  const items = await fs.readdir(srcDirectory);
  items.forEach(function (childItemName) {
    copyDirNested(
      path.join(srcDirectory, childItemName),
      path.join(destDir, childItemName)
    );
  });
}

/**
 * @param {string} src
 * @param {string} dest
 */
async function copyDirNested(src, dest) {
  var exists = fsSync.existsSync(src);
  var stats = exists && fsSync.statSync(src);
  var isDirectory = exists && stats.isDirectory();
  if (isDirectory) {
    await tryMkdir(dest);
    const items = await fs.readdir(src);
    items.forEach(function (childItemName) {
      copyDirNested(
        path.join(src, childItemName),
        path.join(dest, childItemName)
      );
    });
  } else {
    fs.copyFile(src, dest);
  }
}

module.exports = {
  writeFile: fs.writeFile,
  readFile: fs.readFile,
  copyFile: fs.copyFile,
  exists: fs.exists,
  tryMkdir,
  copyDirFlat,
  copyDirNested,
};
