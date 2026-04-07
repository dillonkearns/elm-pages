import * as assert from "node:assert";
import * as fs from "node:fs";
import * as http from "node:http";
import * as os from "node:os";
import * as path from "node:path";
import { afterEach, describe, it } from "vitest";
import {
  discoverProgramTestModules,
  findProgramTestValues,
  findTuiTestValues,
} from "../src/commands/shared.js";
import {
  createTestViewerServerApp,
  renderStaticViewerHtml,
  renderStaticViewerPreviewHtml,
  TEST_VIEWER_PREVIEW_ROUTE,
  TEST_VIEWER_ROUTE,
  TEST_VIEWER_SCRIPT_ROUTE,
} from "../src/commands/test-view.js";

const tempDirs = [];
const originalCwd = process.cwd();

afterEach(() => {
  process.chdir(originalCwd);
  while (tempDirs.length > 0) {
    fs.rmSync(tempDirs.pop(), { recursive: true, force: true });
  }
});

function writeElmModule(source) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "elm-pages-discovery-"));
  const filePath = path.join(tempDir, "Example.elm");
  tempDirs.push(tempDir);
  fs.writeFileSync(filePath, source);
  return filePath;
}

describe("test value discovery", () => {
  it("finds ProgramTest values with multiline type annotations", () => {
    const filePath = writeElmModule(`module Example exposing (programTest, helper)

programTest :
    TestApp.ProgramTest
programTest =
    Debug.todo "not evaluated"

helper : Int
helper =
    1
`);

    assert.deepStrictEqual(findProgramTestValues(filePath), ["programTest"]);
  });

  it("finds TuiTest values with multiline type annotations", () => {
    const filePath = writeElmModule(`module Example exposing (tuiTest, helper)

tuiTest :
    Tui.Test.TuiTest
        Model
        Msg
tuiTest =
    Debug.todo "not evaluated"

helper : Int
helper =
    1
`);

    assert.deepStrictEqual(findTuiTestValues(filePath), ["tuiTest"]);
  });

  it("discovers ProgramTests from tests and snapshot-tests/src", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "elm-pages-program-tests-"));
    tempDirs.push(tempDir);

    fs.mkdirSync(path.join(tempDir, "tests"), { recursive: true });
    fs.mkdirSync(path.join(tempDir, "snapshot-tests/src"), { recursive: true });

    fs.writeFileSync(
      path.join(tempDir, "tests", "FrameworkTests.elm"),
      `module FrameworkTests exposing (counterTest)

counterTest : TestApp.ProgramTest
counterTest =
    Debug.todo "not evaluated"
`
    );

    fs.writeFileSync(
      path.join(tempDir, "snapshot-tests/src", "VisualTests.elm"),
      `module VisualTests exposing (responsiveTest)

responsiveTest :
    TestApp.ProgramTest
responsiveTest =
    Debug.todo "not evaluated"
`
    );

    process.chdir(tempDir);

    assert.deepStrictEqual(discoverProgramTestModules(), [
      {
        moduleName: "FrameworkTests",
        file: "tests/FrameworkTests.elm",
        values: ["counterTest"],
      },
      {
        moduleName: "VisualTests",
        file: "snapshot-tests/src/VisualTests.elm",
        values: ["responsiveTest"],
      },
    ]);
  });

  it("renders standalone viewer HTML with a preview sync shell", () => {
    const html = renderStaticViewerHtml({
      scriptSrc: "viewer.js",
      previewSrc: "viewer-preview.html",
    });

    assert.match(html, /<script src="viewer\.js"><\/script>/);
    assert.match(html, /var previewSrc = "viewer-preview\.html";/);
    assert.match(html, /document\.querySelector\("\.page-body"\)/);
    assert.match(html, /iframe\.contentDocument/);
  });

  it("renders standalone viewer HTML with assertion/scope highlight support", () => {
    const html = renderStaticViewerHtml({
      scriptSrc: "viewer.js",
      previewSrc: "viewer-preview.html",
    });

    assert.match(html, /interaction-selectors/);
    assert.match(html, /__elm-pages-highlight-scope/);
  });

  it("renders a standalone preview document", () => {
    const html = renderStaticViewerPreviewHtml({
      headTags:
        '<link rel="stylesheet" href="/style.css" /><script src="/assets/viewer.js"></script>',
      baseHref: "../",
    });

    assert.match(html, /id="preview-root"/);
    assert.match(html, /<link rel="stylesheet" href="\.\.\/style\.css" \/>/);
    assert.match(html, /<script src="\.\.\/assets\/viewer\.js"><\/script>/);
  });

  it("serves the preview route through vite html transforms", async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "elm-pages-test-view-server-"));
    tempDirs.push(tempDir);

    const viewerScriptPath = path.join(tempDir, "viewer.js");
    fs.writeFileSync(viewerScriptPath, 'console.log("viewer loaded");');

    let transformed = null;

    const app = createTestViewerServerApp({
      viewerHtml: renderStaticViewerHtml({
        scriptSrc: TEST_VIEWER_SCRIPT_ROUTE,
        previewSrc: TEST_VIEWER_PREVIEW_ROUTE,
        previewBaseHref: "/",
      }),
      previewHtml: renderStaticViewerPreviewHtml({
        headTags: '<meta name="generator" content="test" />',
        baseHref: "/",
      }),
      viewerScriptPath,
      vite: {
        middlewares(req, res, next) {
          next();
        },
        async transformIndexHtml(url, html) {
          transformed = { url, html };
          return html.replace(
            "</head>",
            '<meta name="transformed" content="yes" /></head>'
          );
        },
      },
    });

    const server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

    try {
      const address = server.address();
      const baseUrl = `http://127.0.0.1:${address.port}`;

      const viewerHtml = await fetch(baseUrl + TEST_VIEWER_ROUTE).then((response) =>
        response.text()
      );
      const previewHtml = await fetch(baseUrl + TEST_VIEWER_PREVIEW_ROUTE).then((response) =>
        response.text()
      );
      const scriptText = await fetch(baseUrl + TEST_VIEWER_SCRIPT_ROUTE).then((response) =>
        response.text()
      );

      assert.match(viewerHtml, /_tests-preview/);
      assert.match(previewHtml, /name="transformed" content="yes"/);
      assert.deepStrictEqual(transformed && transformed.url, TEST_VIEWER_PREVIEW_ROUTE);
      assert.match(scriptText, /viewer loaded/);
    } finally {
      await new Promise((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve()))
      );
    }
  });
});
