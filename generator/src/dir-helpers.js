const util = require("util");
const fsSync = require("fs");
const fs = {
  writeFile: util.promisify(fsSync.writeFile),
  writeFileSync: fsSync.writeFileSync,
  rm: util.promisify(fsSync.unlinkSync),
  mkdir: util.promisify(fsSync.mkdir),
  readFile: util.promisify(fsSync.readFile),
  copyFile: util.promisify(fsSync.copyFile),
  exists: util.promisify(fsSync.exists),
  existsSync: fsSync.existsSync,
  readdir: util.promisify(fsSync.readdir),
};

/**
 * @param {import("fs").PathLike} dirName
 */
async function tryMkdir(dirName) {
  const exists = await fs.exists(dirName);
  if (!exists) {
    await fs.mkdir(dirName, { recursive: true });
  }
}

function fileExists(file) {
  return fsSync.promises
    .access(file, fsSync.constants.F_OK)
    .then(() => true)
    .catch(() => false);
}

/**
 * @param {string} filePath
 * @param {string} data
 */
function writeFileSyncSafe(filePath, data) {
  fsSync.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, data);
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
  writeFileSync: fs.writeFileSync,
  readFile: fs.readFile,
  readFileSync: fsSync.readFileSync,
  copyFile: fs.copyFile,
  exists: fs.exists,
  writeFileSyncSafe,
  tryMkdir,
  copyDirFlat,
  copyDirNested,
  rmSync: fs.rm,
  rm: fs.rm,
  existsSync: fs.existsSync,
  fileExists: fileExists,
};
