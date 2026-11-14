/**
 * The type fingerprint tells the dev server whether new code can be hot
 * reloaded into a running app, or whether the app's types changed so the page
 * must be loaded again. Tested against the real output of the installed
 * `lamdera` compiler, in the modes the dev server compiles in.
 */

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import {
  typeFingerprint,
  withTypeFingerprint,
} from "../src/type-fingerprint.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureDir = path.join(__dirname, "fixtures/type-fingerprint");

/** @type {string} */
let projectDir;

beforeAll(() => {
  projectDir = fs.mkdtempSync(path.join(os.tmpdir(), "elm-pages-types-"));
  fs.mkdirSync(path.join(projectDir, "src"));
  fs.copyFileSync(
    path.join(fixtureDir, "elm.json"),
    path.join(projectDir, "elm.json")
  );
});

afterAll(() => {
  fs.rmSync(projectDir, { recursive: true, force: true });
});

const baseline = {
  model: "{ count : Int, items : List Item }",
  msg: "Increment | Reset",
  init: "{ count = 0, items = [] }",
  update: "{ model | count = model.count + 1 }",
  label: "v1",
  item: "{ name : String }",
};

/**
 * Compile the fixture app with some of its parts replaced.
 *
 * @param {Partial<typeof baseline>} changes
 * @param {string[]} [flags] - extra `lamdera make` flags
 * @returns {string} the compiled JS
 */
function compile(changes = {}, flags = []) {
  const parts = { ...baseline, ...changes };
  const fill = (/** @type {string} */ template) =>
    fs
      .readFileSync(path.join(fixtureDir, template), "utf8")
      .replace("__MODEL__", parts.model)
      .replace("__MSG__", parts.msg)
      .replace("__INIT__", parts.init)
      .replace("__UPDATE__", parts.update)
      .replace("__LABEL__", parts.label)
      .replace("__ITEM__", parts.item);
  fs.writeFileSync(
    path.join(projectDir, "src/App.elm"),
    fill("App.elm.template")
  );
  fs.writeFileSync(
    path.join(projectDir, "src/Item.elm"),
    fill("Item.elm.template")
  );
  const output = path.join(projectDir, "app.js");
  const result = spawnSync(
    "lamdera",
    ["make", "src/App.elm", `--output=${output}`, ...flags],
    { cwd: projectDir, encoding: "utf8" }
  );
  if (result.status !== 0) {
    throw new Error(
      `lamdera make failed:\n${result.stdout}\n${result.stderr}\n${result.error || ""}`
    );
  }
  return fs.readFileSync(output, "utf8");
}

for (const [mode, flags] of /** @type {[string, string[]][]} */ ([
  ["elm-pages dev", []],
  ["elm-pages dev --debug", ["--debug"]],
])) {
  describe(`type fingerprint (${mode})`, { timeout: 120000 }, () => {
    /** @type {string} */
    let original;

    beforeAll(() => {
      original = typeFingerprint(compile({}, flags));
    });

    it("stays the same when the same code is compiled again", () => {
      expect(typeFingerprint(compile({}, flags))).toBe(original);
    });

    it("stays the same when only the body of update changes", () => {
      const changed = compile(
        { update: "{ model | count = model.count + 100 }", label: "v2" },
        flags
      );
      expect(typeFingerprint(changed)).toBe(original);
    });

    it("changes when a field is added to Model", () => {
      const changed = compile(
        {
          model: "{ count : Int, items : List Item, label : String }",
          init: '{ count = 0, items = [], label = "" }',
        },
        flags
      );
      expect(typeFingerprint(changed)).not.toBe(original);
    });

    it("changes when the type of a Model field changes", () => {
      const changed = compile(
        {
          model: "{ count : Float, items : List Item }",
          init: "{ count = 0, items = [] }",
        },
        flags
      );
      expect(typeFingerprint(changed)).not.toBe(original);
    });

    it("changes when a variant is added to Msg", () => {
      const changed = compile({ msg: "Increment | Reset | Double" }, flags);
      expect(typeFingerprint(changed)).not.toBe(original);
    });

    it("changes when a variant of Msg gets an argument", () => {
      const changed = compile({ msg: "Increment | Reset | SetTo Int" }, flags);
      expect(typeFingerprint(changed)).not.toBe(
        typeFingerprint(compile({ msg: "Increment | Reset | SetTo String" }, flags))
      );
    });

    it("changes when a type from another module that Model uses changes", () => {
      const changed = compile({ item: "{ name : String, done : Bool }" }, flags);
      expect(typeFingerprint(changed)).not.toBe(original);
    });

    it("accepts a Model that holds a function", () => {
      const changed = compile(
        {
          model: "{ count : Int, items : List Item, next : Int -> Int }",
          init: "{ count = 0, items = [], next = identity }",
        },
        flags
      );
      expect(typeFingerprint(changed)).not.toBe(original);
    });
  });
}

describe("withTypeFingerprint", () => {
  it("makes the code set the fingerprint on the scope it runs in", () => {
    const code = withTypeFingerprint("this.ran = true;");
    /** @type {Record<string, unknown>} */
    const scope = {};

    new Function(code).call(scope);

    expect(scope.ran).toBe(true);
    expect(scope.__elmPagesTypeFingerprint).toBe(
      typeFingerprint("this.ran = true;")
    );
  });
});
