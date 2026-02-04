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

/**
 * Check if a file exists.
 * @param {string} filePath
 * @returns {Promise<boolean>}
 */
export function fileExists(filePath) {
  return fs.promises
    .access(filePath, fs.constants.F_OK)
    .then(() => true)
    .catch(() => false);
}

/**
 * Write a file only if its content has changed.
 * This avoids updating the mtime unnecessarily, which can trigger unnecessary recompilation.
 * @param {string} filePath
 * @param {string} content
 * @returns {Promise<boolean>} - Returns true if the file was written, false if skipped
 */
export async function writeFileIfChanged(filePath, content) {
  if (
    !(await fileExists(filePath)) ||
    (await fs.promises.readFile(filePath, "utf8")) !== content
  ) {
    await fs.promises.writeFile(filePath, content);
    return true;
  }
  return false;
}

/**
 * Copy a file only if the source is newer than the destination.
 * @param {string} src - Source file path
 * @param {string} dest - Destination file path
 * @returns {Promise<boolean>} - Returns true if copied, false if skipped
 */
export async function copyFileIfNewer(src, dest) {
  try {
    const srcStat = await fs.promises.stat(src);
    try {
      const destStat = await fs.promises.stat(dest);
      // Skip if destination exists and source mtime <= dest mtime
      if (srcStat.mtimeMs <= destStat.mtimeMs) {
        return false;
      }
    } catch (e) {
      // Destination doesn't exist, proceed with copy
    }
    await fs.promises.copyFile(src, dest);
    return true;
  } catch (e) {
    // Source doesn't exist or other error
    throw e;
  }
}

/**
 * Sync a directory by copying only newer files and removing files that no longer exist in source.
 * @param {string[]} sourceFiles - Array of source file paths
 * @param {string} destDir - Destination directory
 * @param {(file: string) => string} getDestName - Function to get destination filename from source path
 * @returns {Promise<{copied: number, skipped: number, removed: number}>}
 */
export async function syncFilesToDirectory(sourceFiles, destDir, getDestName) {
  ensureDirSync(destDir);

  const sourceBasenames = new Set(sourceFiles.map(getDestName));
  const stats = { copied: 0, skipped: 0, removed: 0 };

  // Copy newer files
  for (const srcFile of sourceFiles) {
    const destPath = `${destDir}/${getDestName(srcFile)}`;
    const wasCopied = await copyFileIfNewer(srcFile, destPath);
    if (wasCopied) {
      stats.copied++;
    } else {
      stats.skipped++;
    }
  }

  // Remove files in dest that are not in source
  try {
    const destFiles = await fs.promises.readdir(destDir);
    for (const destFile of destFiles) {
      if (!sourceBasenames.has(destFile)) {
        await fs.promises.unlink(`${destDir}/${destFile}`);
        stats.removed++;
      }
    }
  } catch (e) {
    // Directory might not exist yet
  }

  return stats;
}
