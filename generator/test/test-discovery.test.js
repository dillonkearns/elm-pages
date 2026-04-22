import * as assert from "node:assert";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { afterEach, describe, it } from "vitest";
import {
  classifyAllTestValues,
  discoverAllTestModules,
  discoverProgramTestModules,
  findProgramTestValues,
  findTuiTestValues,
  findVanillaTestValues,
  stripCommentsAndStrings,
} from "../src/commands/shared.js";

const tempDirs = [];
const originalCwd = process.cwd();

afterEach(() => {
  process.chdir(originalCwd);
  while (tempDirs.length > 0) {
    fs.rmSync(tempDirs.pop(), { recursive: true, force: true });
  }
});

function writeElmModule(source, name = "Example") {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "elm-pages-discovery-"));
  const filePath = path.join(tempDir, `${name}.elm`);
  tempDirs.push(tempDir);
  fs.writeFileSync(filePath, source);
  return filePath;
}

describe("test value discovery", () => {
  it("finds ProgramTest values with multiline type annotations", async () => {
    const filePath = writeElmModule(`module Example exposing (programTest, helper)

programTest :
    TestApp.ProgramTest
programTest =
    Debug.todo "not evaluated"

helper : Int
helper =
    1
`);

    assert.deepStrictEqual(await findProgramTestValues(filePath), [
      "programTest",
    ]);
  });

  it("finds TuiTest values with multiline type annotations", async () => {
    const filePath = writeElmModule(`module Example exposing (tuiTest, helper)

tuiTest :
    Test.Tui.Test
tuiTest =
    Debug.todo "not evaluated"

helper : Int
helper =
    1
`);

    assert.deepStrictEqual(await findTuiTestValues(filePath), ["tuiTest"]);
  });

  it("discovers ProgramTests from tests and snapshot-tests/src", async () => {
    const tempDir = fs.mkdtempSync(
      path.join(os.tmpdir(), "elm-pages-program-tests-")
    );
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

    assert.deepStrictEqual(await discoverProgramTestModules(), [
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

  it("ignores annotations hidden in line comments", async () => {
    const filePath = writeElmModule(`module Example exposing (realTest)

-- tuiTest : TuiTest.Test
-- tuiTest = Debug.todo "not real"

realTest : Test
realTest =
    Debug.todo "not evaluated"
`);

    assert.deepStrictEqual(await findTuiTestValues(filePath), []);
    assert.deepStrictEqual(await findVanillaTestValues(filePath), ["realTest"]);
  });

  it("ignores annotations hidden in nested block comments", async () => {
    const filePath = writeElmModule(`module Example exposing (realTest)

{- Some doc

   {- even nested
      myTest : TestApp.ProgramTest
      myTest = Debug.todo "not real"
   -}

   keep reading
-}

realTest : Test
realTest =
    Debug.todo "not evaluated"
`);

    assert.deepStrictEqual(await findProgramTestValues(filePath), []);
    assert.deepStrictEqual(await findVanillaTestValues(filePath), ["realTest"]);
  });

  it("ignores fake annotations buried in multiline strings with exposing (..)", async () => {
    const filePath = writeElmModule(`module Example exposing (..)

docstring : String
docstring =
    """
    myTest : TestApp.ProgramTest
    myTest =
        Debug.todo "not real"
    """

realTest : Test
realTest =
    Debug.todo "not evaluated"
`);

    assert.deepStrictEqual(await findProgramTestValues(filePath), []);
    assert.deepStrictEqual(await findVanillaTestValues(filePath), ["realTest"]);
  });

  it("rejects helpers that take a ProgramTest as input", async () => {
    const filePath = writeElmModule(`module Example exposing (myHelper, myTest)

myHelper : ProgramTest model msg -> Int
myHelper _ =
    0

myTest : TestApp.ProgramTest
myTest =
    Debug.todo "not evaluated"
`);

    assert.deepStrictEqual(await findProgramTestValues(filePath), ["myTest"]);
  });

  it("rejects helpers that return a ProgramTest (function types)", async () => {
    const filePath = writeElmModule(`module Example exposing (buildTest, myTest)

buildTest : Int -> TestApp.ProgramTest
buildTest _ =
    Debug.todo "not evaluated"

myTest : TestApp.ProgramTest
myTest =
    Debug.todo "not evaluated"
`);

    assert.deepStrictEqual(await findProgramTestValues(filePath), ["myTest"]);
  });

  it("classifies a multi-line annotation with record-field colons", async () => {
    const filePath = writeElmModule(`module Example exposing (loginTest)

loginTest :
    ProgramTest
        { email : String
        , password : String
        , loggedIn : Bool
        }
        LoginMsg
loginTest =
    Debug.todo "not evaluated"
`);

    assert.deepStrictEqual(await findProgramTestValues(filePath), [
      "loginTest",
    ]);
  });

  it("handles exposing (Type(..)) in exports", async () => {
    const filePath = writeElmModule(`module Example exposing (Msg(..), myTest)

type Msg
    = Go
    | Stop

myTest : Test
myTest =
    Debug.todo "not evaluated"
`);

    assert.deepStrictEqual(await findVanillaTestValues(filePath), ["myTest"]);
  });

  it("collects un-annotated exposed values per file for hard-fail reporting", async () => {
    const tempDir = fs.mkdtempSync(
      path.join(os.tmpdir(), "elm-pages-warn-")
    );
    tempDirs.push(tempDir);
    fs.mkdirSync(path.join(tempDir, "tests"), { recursive: true });
    fs.writeFileSync(
      path.join(tempDir, "tests", "Mixed.elm"),
      `module Mixed exposing (classified, forgotten)

classified : Test
classified =
    Debug.todo ""

forgotten =
    Debug.todo ""
`
    );
    fs.writeFileSync(
      path.join(tempDir, "tests", "OnlyMissing.elm"),
      `module OnlyMissing exposing (oops)

oops =
    Debug.todo ""
`
    );

    process.chdir(tempDir);
    const d = await discoverAllTestModules();
    assert.deepStrictEqual(
      d.missingAnnotations.map(({ file, names }) => ({ file, names })),
      [
        { file: "tests/Mixed.elm", names: ["forgotten"] },
        { file: "tests/OnlyMissing.elm", names: ["oops"] },
      ]
    );
  });

  it("tracks un-annotated names under missingAnnotation", async () => {
    const filePath = writeElmModule(`module Example exposing (forgotten, myTest)

forgotten =
    Debug.todo ""

myTest : Test
myTest =
    Debug.todo "not evaluated"
`);

    const result = await classifyAllTestValues(filePath);
    assert.deepStrictEqual(result.vanilla, ["myTest"]);
    assert.deepStrictEqual(result.missingAnnotation, ["forgotten"]);
    assert.deepStrictEqual(result.nonTest, []);
  });

  it("passes annotated non-test values through as nonTest (helpers)", async () => {
    const filePath = writeElmModule(`module Example exposing (helper, myTest)

helper : Int -> Int
helper x =
    x + 1

myTest : Test
myTest =
    Debug.todo "not evaluated"
`);

    const result = await classifyAllTestValues(filePath);
    assert.deepStrictEqual(result.vanilla, ["myTest"]);
    assert.deepStrictEqual(result.nonTest, ["helper"]);
    assert.deepStrictEqual(result.missingAnnotation, []);
  });
});

describe("stripCommentsAndStrings", () => {
  it("blanks line-comment bodies and keeps newlines", () => {
    const stripped = stripCommentsAndStrings(
      "a = 1 -- comment here\nb = 2\n"
    );
    assert.strictEqual(
      stripped,
      "a = 1                \nb = 2\n"
    );
  });

  it("blanks nested block comments", () => {
    const stripped = stripCommentsAndStrings("{- outer {- inner -} still -}ok");
    assert.strictEqual(stripped, "                             ok");
  });

  it("blanks string bodies but preserves delimiters", () => {
    const stripped = stripCommentsAndStrings('x = "hello\\nworld"');
    // Content between "..." becomes spaces; delimiters kept.
    assert.strictEqual(stripped, 'x = "            "');
  });

  it("blanks triple-quoted string bodies and preserves newlines", () => {
    const stripped = stripCommentsAndStrings('"""a\nb\nc"""');
    assert.strictEqual(stripped, "    \n \n    ");
  });
});
