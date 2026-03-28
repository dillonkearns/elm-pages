import * as assert from "node:assert";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { afterEach, describe, it } from "vitest";
import {
  discoverProgramTestModules,
  findProgramTestValues,
  findTuiTestValues,
} from "../src/commands/shared.js";
import {
  renderStaticViewerHtml,
  renderStaticViewerPreviewHtml,
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

  it("renders a standalone preview document", () => {
    const html = renderStaticViewerPreviewHtml();

    assert.match(html, /id="preview-root"/);
  });
});
