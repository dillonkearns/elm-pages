import * as fs from "node:fs";

export function ensureDirSync(dirpath) {
  try {
    fs.mkdirSync(dirpath, { recursive: true });
  } catch (err) {
    if (err.code !== "EEXIST") throw err;
  }
}

export function deleteIfExists(/** @type string */ filePath) {
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }
}
