import * as util from "util";
import * as fsSync from "fs";
import * as path from "path";

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
export async function tryMkdir(dirName) {
  const exists = await fs.exists(dirName);
  if (!exists) {
    await fs.mkdir(dirName, { recursive: true });
  }
}

export function fileExists(file) {
  return fsSync.promises
    .access(file, fsSync.constants.F_OK)
    .then(() => true)
    .catch(() => false);
}

/**
 * @param {string} filePath
 * @param {string} data
 */
export function writeFileSyncSafe(filePath, data) {
  fsSync.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, data);
}

/**
 * @param {string} srcDirectory
 * @param {string} destDir
 */
export async function copyDirFlat(srcDirectory, destDir) {
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
export async function copyDirNested(src, dest) {
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

