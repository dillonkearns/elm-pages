/**
 * Hot reloading in `elm-pages dev`, tested against the real output of the
 * installed `lamdera` compiler.
 *
 * Lamdera builds hot reloading into the compiled code (`Elm.hot.reload`), and
 * the dev server's `hmr.js` calls it when new code arrives.
 */

import { describe, it, expect, beforeAll, afterAll, vi } from "vitest";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as vm from "node:vm";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtureDir = path.join(__dirname, "fixtures/hot-reload");
const hmrClientCode = fs.readFileSync(
  path.join(__dirname, "../static-code/hmr.js"),
  "utf8"
);

/** @type {string} */
let projectDir;

beforeAll(() => {
  projectDir = fs.mkdtempSync(path.join(os.tmpdir(), "elm-pages-hot-reload-"));
  fs.mkdirSync(path.join(projectDir, "src"));
  fs.copyFileSync(
    path.join(fixtureDir, "elm.json"),
    path.join(projectDir, "elm.json")
  );
  fs.copyFileSync(
    path.join(fixtureDir, "src/NavApp.elm"),
    path.join(projectDir, "src/NavApp.elm")
  );
});

afterAll(() => {
  fs.rmSync(projectDir, { recursive: true, force: true });
});

/**
 * Compile a module with the installed `lamdera`, the same way the dev server
 * compiles the client (no `--optimize`).
 *
 * @param {string} moduleName
 * @returns {string} the compiled JS
 */
function compile(moduleName) {
  const output = path.join(projectDir, `${moduleName}.js`);
  const result = spawnSync(
    "lamdera",
    ["make", `src/${moduleName}.elm`, `--output=${output}`],
    { cwd: projectDir, encoding: "utf8" }
  );
  if (result.status !== 0) {
    throw new Error(
      `lamdera make failed:\n${result.stdout}\n${result.stderr}\n${result.error || ""}`
    );
  }
  return fs.readFileSync(output, "utf8");
}

/**
 * @param {string} version
 * @returns {string} the compiled JS for that version of the Counter worker
 */
function compileCounter(version) {
  const template = fs.readFileSync(
    path.join(fixtureDir, "Counter.elm.template"),
    "utf8"
  );
  fs.writeFileSync(
    path.join(projectDir, "src/Counter.elm"),
    template.replace("__VERSION__", version)
  );
  return compile("Counter");
}

/**
 * A stand-in for the browser page: just enough globals to load the dev
 * server's `hmr.js` and run compiled Elm code.
 */
function createPage() {
  const page = vm.createContext({ console, setTimeout, clearTimeout });
  page.window = page;
  page.pageReloads = 0;
  page.location = {
    reload() {
      page.pageReloads += 1;
    },
  };
  vm.runInContext(hmrClientCode, page, { filename: "hmr.js" });
  return page;
}

describe("hot reloading with the installed lamdera", { timeout: 120000 }, () => {
  it("is built into a compiled Browser.application", () => {
    const page = createPage();

    vm.runInContext(compile("NavApp"), page, { filename: "elm.js" });

    expect(typeof page.Elm.NavApp.init).toBe("function");
    expect(typeof page.Elm.hot.reload).toBe("function");
  });

  it("swaps in new code and keeps the running app's state", async () => {
    const page = createPage();
    vm.runInContext(compileCounter("v1"), page, { filename: "elm.js" });
    /** @type {string[]} */
    const reports = [];
    vm.runInContext("var app = Elm.Counter.init({});", page);
    page.app.ports.report.subscribe((/** @type {string} */ message) =>
      reports.push(message)
    );

    page.app.ports.increment.send(null);
    page.app.ports.increment.send(null);
    await vi.waitFor(() => expect(reports).toEqual(["v1:1", "v1:2"]));

    await page.applyElmJs(compileCounter("v2"));
    page.app.ports.increment.send(null);

    await vi.waitFor(() =>
      expect(reports).toEqual(["v1:1", "v1:2", "v2:3"])
    );
    expect(page.pageReloads).toBe(0);
  });

  it("reloads the page when the new code cannot be swapped in", async () => {
    const page = createPage();
    vm.runInContext(compileCounter("v1"), page, { filename: "elm.js" });
    vm.runInContext("var app = Elm.Counter.init({});", page);
    const quietConsole = vi.spyOn(console, "error").mockImplementation(() => {});

    await page.applyElmJs("throw new Error('this bundle is broken');");

    quietConsole.mockRestore();
    expect(page.pageReloads).toBe(1);
  });
});
