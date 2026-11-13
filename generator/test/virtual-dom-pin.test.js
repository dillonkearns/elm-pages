/**
 * Why elm/virtual-dom is capped in the package's elm.json
 * (elm.json cannot hold comments, so the explanation lives here).
 *
 * Lamdera does not use the published elm/virtual-dom code. It swaps in its
 * own copy, based on https://github.com/lydell/elm-safe-virtual-dom. Each
 * Lamdera release only knows the elm/virtual-dom versions up to the one its
 * copy was made from, and it refuses to compile a project whose elm.json asks
 * for a newer one:
 *
 *     "elm/virtual-dom": "1.0.0 <= v <= 1.0.5"
 *     But your elm.json contains: "elm/virtual-dom": "1.0.6"
 *     You need to update the Lamdera compiler.
 *
 * If the package allowed a newer elm/virtual-dom, `elm install` and
 * `elm-json upgrade` would pick it and every elm-pages app would stop
 * compiling. So the upper bound has to match the newest version that the
 * oldest Lamdera we support accepts.
 *
 * Raise the bound only together with `minimumLamderaVersion` (see
 * generator/src/lamdera-version.js), after checking what that Lamdera
 * release accepts. Then update this test and the note in the README.
 */

import { describe, it, expect } from "vitest";
import * as fs from "node:fs";
import { fileURLToPath } from "node:url";
import * as path from "node:path";
import { minimumLamderaVersion } from "../src/lamdera-version.js";

const repoRoot = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  ".."
);

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), "utf8"));
}

/** The newest elm/virtual-dom that Lamdera 1.5.0 accepts. */
const newestVirtualDomLamderaAccepts = "1.0.5";
const firstVirtualDomLamderaRejects = "1.0.6";

describe("elm/virtual-dom version", () => {
  it("was checked against the Lamdera version we require", () => {
    expect(
      minimumLamderaVersion,
      "The minimum Lamdera version changed. Check which elm/virtual-dom versions it accepts and update this test, elm.json and the README."
    ).toEqual([1, 5, 0]);
  });

  it("is capped in the package at the newest version Lamdera accepts", () => {
    expect(
      readJson("elm.json").dependencies["elm/virtual-dom"],
      "Lamdera refuses to compile with a newer elm/virtual-dom. See the comment at the top of this file before changing the range."
    ).toBe(
      `${newestVirtualDomLamderaAccepts} <= v < ${firstVirtualDomLamderaRejects}`
    );
  });

  it("is one Lamdera accepts in the starter template", () => {
    const template = readJson("generator/template/elm.json");
    const version = {
      ...template.dependencies.direct,
      ...template.dependencies.indirect,
    }["elm/virtual-dom"];
    expect(
      version,
      "The starter template must use an elm/virtual-dom that Lamdera can compile. See the comment at the top of this file."
    ).toBe(newestVirtualDomLamderaAccepts);
  });
});
