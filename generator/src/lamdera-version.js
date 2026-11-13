import { spawnSync } from "node:child_process";
import { isOlderVersion } from "./version.js";

/** The oldest Lamdera this version of elm-pages works with. */
export const minimumLamderaVersion = [1, 5, 0];

/**
 * Read the Lamdera version out of the first line of `lamdera --help`, which
 * looks like "Hi, thank you for trying out Lamdera 1.5.0 on Elm 0.19.3."
 * (`lamdera --version` only prints the Elm version.)
 *
 * @param {string} helpOutput
 * @returns {number[] | null}
 */
export function parseLamderaVersion(helpOutput) {
  const match = /Lamdera (\d+)\.(\d+)\.(\d+)/.exec(helpOutput);
  return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : null;
}

/**
 * @param {string} helpOutput - the output of `lamdera --help`
 * @returns {string | null} an error message if this Lamdera is too old
 */
export function lamderaVersionProblem(helpOutput) {
  const version = parseLamderaVersion(helpOutput);
  if (version === null || !isOlderVersion(version, minimumLamderaVersion)) {
    return null;
  }
  return `elm-pages needs Lamdera ${minimumLamderaVersion.join(".")} or later, but I found Lamdera ${version.join(".")} on the PATH.

To update it in your project, run:

    npm install --save-dev lamdera@latest

If you need to stay on an older Lamdera, use an older version of the elm-pages NPM and Elm packages.`;
}

let alreadyChecked = false;

/**
 * Throw a helpful error if the `lamdera` on the PATH is too old.
 * Call this after checking that `lamdera` is there at all.
 */
export function requireSupportedLamderaVersion() {
  if (alreadyChecked) {
    return;
  }
  const result = spawnSync("lamdera", ["--help"], { encoding: "utf8" });
  const problem = lamderaVersionProblem(result.stdout || "");
  if (problem) {
    throw new Error(problem);
  }
  alreadyChecked = true;
}
