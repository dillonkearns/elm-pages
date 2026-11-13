import { spawnSync } from "node:child_process";
import { isOlderVersion } from "./version.js";

/**
 * The oldest elm-review this version of elm-pages works with.
 *
 * elm-pages builds elm-review's rules with Lamdera. With elm-review 2.13.2 and
 * older, the rules then report nothing at all, with no error, so the build
 * would quietly skip frozen views and dead code elimination.
 */
export const minimumElmReviewVersion = [2, 13, 3];

/**
 * @param {string} versionOutput - the output of `elm-review --version`
 * @returns {number[] | null}
 */
export function parseElmReviewVersion(versionOutput) {
  const match = /^\s*(\d+)\.(\d+)\.(\d+)/.exec(versionOutput);
  return match ? [Number(match[1]), Number(match[2]), Number(match[3])] : null;
}

/**
 * @param {string} versionOutput - the output of `elm-review --version`
 * @returns {string | null} an error message if this elm-review is too old
 */
export function elmReviewVersionProblem(versionOutput) {
  const version = parseElmReviewVersion(versionOutput);
  if (version === null || !isOlderVersion(version, minimumElmReviewVersion)) {
    return null;
  }
  return `elm-pages needs elm-review ${minimumElmReviewVersion.join(".")} or later, but I found elm-review ${version.join(".")} on the PATH.

Older versions find nothing when their rules are built with Lamdera, so frozen views and dead code elimination would be skipped without any warning.

To update it in your project, run:

    npm install --save-dev elm-review@latest`;
}

let alreadyChecked = false;

/**
 * Throw a helpful error if the `elm-review` on the PATH is too old.
 * Call this after checking that `elm-review` is there at all.
 */
export function requireSupportedElmReviewVersion() {
  if (alreadyChecked) {
    return;
  }
  const result = spawnSync("elm-review", ["--version"], { encoding: "utf8" });
  const problem = elmReviewVersionProblem(result.stdout || "");
  if (problem) {
    throw new Error(problem);
  }
  alreadyChecked = true;
}
