/**
 * A fingerprint of the types the running app keeps in memory (its `Model`,
 * `Msg` and page data), read out of the compiled client code.
 *
 * Hot reloading swaps new `view` and `update` functions into a running app
 * and keeps its model. That only works while the types stay the same: new
 * code that expects a field the old model does not have would run on a model
 * that does not fit. So when the fingerprint of new code differs from that of
 * the code on the page, the dev server's `hmr.js` loads the page again instead
 * of hot reloading.
 *
 * Where the fingerprint comes from: Lamdera generates Wire codecs for every
 * type, straight from the type's definition. The dev server's generated
 * `Main.elm` keeps the codecs for `Model` and `Msg` in the compiled code (see
 * `keepTypesForHotReload` in `codegen/GenerateMain.elm`), next to the ones for
 * page data that are always there. Those codecs, and the codecs of every type
 * they mention, change exactly when the types do, and stay the same when only
 * a function body changes.
 */

import * as crypto from "node:crypto";

/** The property that compiled client code sets on the scope it runs in. */
export const fingerprintProperty = "__elmPagesTypeFingerprint";

// A top-level definition in compiled Elm code starts at the beginning of a
// line with `var` or `function`. This matches the ones that are Wire codecs:
//   var $author$project$Main$w3_encode_Model = ...
//   function $author$project$Main$w3e_Model(v) { ... }
const wireCodecDefinition = /^(?:var|function) [\w$]*\$w3(?:_encode|_decode|e|d)_/;

/**
 * @param {string} compiledElmCode - the JavaScript that `lamdera make` wrote
 * @returns {string}
 */
export function typeFingerprint(compiledElmCode) {
  const codecs = compiledElmCode
    .split(/\n(?=var |function )/)
    .filter((definition) => wireCodecDefinition.test(definition))
    .sort();
  return crypto
    .createHash("sha256")
    .update(codecs.join("\n"))
    .digest("hex")
    .slice(0, 16);
}

/**
 * Add a line to compiled client code that records its type fingerprint on the
 * scope the code runs in. That is `window` when the page loads the code with a
 * script tag, and a new empty object when `hmr.js` evaluates new code to
 * decide whether it can be hot reloaded.
 *
 * @param {string} compiledElmCode
 * @returns {string}
 */
export function withTypeFingerprint(compiledElmCode) {
  return `${compiledElmCode}\n;this.${fingerprintProperty} = ${JSON.stringify(
    typeFingerprint(compiledElmCode)
  )};\n`;
}
