import * as fs from "node:fs";
import * as path from "node:path";

/** Things the tests need done in Node, for `cy.task`. */
export const tasks = {
  /** Write several files in one go, with nothing else happening in between.
   * @param {Record<string, string>} contentsByFile */
  writeFiles(contentsByFile) {
    for (const [file, contents] of Object.entries(contentsByFile)) {
      fs.writeFileSync(file, contents);
    }
    return null;
  },
  /** @param {string} file */
  deleteFile(file) {
    fs.rmSync(file, { force: true });
    return null;
  },
  /** Delete the files right inside a directory (not its subdirectories).
   * @param {string} directory */
  deleteFilesIn(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.isFile()) {
        fs.rmSync(path.join(directory, entry.name));
      }
    }
    return null;
  },
};
