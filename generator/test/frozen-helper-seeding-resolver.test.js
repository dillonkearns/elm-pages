import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { __testHelpers } from "../src/codegen.js";

const tempDirs = [];

afterEach(() => {
  for (const tempDir of tempDirs) {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
  tempDirs.length = 0;
});

/**
 * @param {Array<string>} sourceDirectories
 * @returns {string}
 */
function createTempProject(sourceDirectories) {
  const tempDir = fs.mkdtempSync(
    path.join(os.tmpdir(), "elm-pages-freeze-resolver-")
  );
  tempDirs.push(tempDir);

  fs.writeFileSync(
    path.join(tempDir, "elm.json"),
    JSON.stringify(
      {
        type: "application",
        "source-directories": sourceDirectories,
        "elm-version": "0.19.1",
        dependencies: {
          direct: { "elm/core": "1.0.5" },
          indirect: {},
        },
        "test-dependencies": {
          direct: {},
          indirect: {},
        },
      },
      null,
      2
    )
  );

  return tempDir;
}

/**
 * @param {string} projectDir
 * @param {string} relativePath
 * @param {string} content
 */
function writeProjectFile(projectDir, relativePath, content) {
  const absolutePath = path.join(projectDir, relativePath);
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  fs.writeFileSync(absolutePath, content);
}

/**
 * @param {string} fileContent
 * @param {string} target
 * @returns {{ start: { line: number, column: number }, end: { line: number, column: number } }}
 */
function findRegionForTarget(fileContent, target) {
  const index = fileContent.indexOf(target);
  if (index < 0) {
    throw new Error(`Could not find target: ${target}`);
  }

  const beforeTarget = fileContent.slice(0, index);
  const line = beforeTarget.split("\n").length;
  const lastLineStart = beforeTarget.lastIndexOf("\n") + 1;
  const column = index - lastLineStart + 1;

  return {
    start: { line, column },
    end: { line, column: column + target.length },
  };
}

/**
 * @param {string} projectDir
 * @param {string} filePath
 * @param {string} target
 */
function makeIssue(projectDir, filePath, target) {
  const absolutePath = path.join(projectDir, filePath);
  const fileContent = fs.readFileSync(absolutePath, "utf8");
  return {
    path: filePath.replace(/\\/g, "/"),
    localPath: filePath.replace(/\\/g, "/"),
    message: "Frozen view codemod: unsupported helper function value or partial application",
    region: findRegionForTarget(fileContent, target),
  };
}

describe("frozen helper seeding resolver", () => {
  it("resolves helper path for qualified alias references", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper as FrozenHelper

view users =
    users |> List.map FrozenHelper.summaryCard
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );

    const issue = makeIssue(
      projectDir,
      issuePath,
      "FrozenHelper.summaryCard"
    );
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "lib/Ui/FrozenHelper.elm",
    ]);
  });

  it("resolves helper path for unqualified exposing imports", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper exposing (summaryCard)

view users =
    users |> List.map summaryCard
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );

    const issue = makeIssue(projectDir, issuePath, "summaryCard");
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "lib/Ui/FrozenHelper.elm",
    ]);
  });

  it("resolves helper path for unqualified exposing all imports", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper exposing (..)

view users =
    users |> List.map summaryCard
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );

    const issue = makeIssue(projectDir, issuePath, "summaryCard");
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "lib/Ui/FrozenHelper.elm",
    ]);
  });

  it("resolves helper path for direct module-qualified imports", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper

view users =
    users |> List.map Ui.FrozenHelper.summaryCard
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );

    const issue = makeIssue(projectDir, issuePath, "Ui.FrozenHelper.summaryCard");
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "lib/Ui/FrozenHelper.elm",
    ]);
  });

  it("resolves helper path for partial application expressions", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper as FrozenHelper

view users =
    users |> List.map (FrozenHelper.summaryCardWithPrefix "User: ")
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCardWithPrefix)

summaryCardWithPrefix prefix user =
    user
`
    );

    const issue = makeIssue(
      projectDir,
      issuePath,
      "FrozenHelper.summaryCardWithPrefix \"User: \""
    );
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "lib/Ui/FrozenHelper.elm",
    ]);
  });

  it("resolves helper path for composition expressions", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper as FrozenHelper

view users =
    users |> List.map (FrozenHelper.summaryCard << identity)
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );

    const issue = makeIssue(
      projectDir,
      issuePath,
      "FrozenHelper.summaryCard << identity"
    );
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "lib/Ui/FrozenHelper.elm",
    ]);
  });

  it("excludes importing callsites for complex unsupported helper expressions", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    writeProjectFile(
      projectDir,
      "lib/Ui/ListView.elm",
      `module Ui.ListView exposing (summaryCards)

import Html.Styled exposing (Html)
import Ui.FrozenHelper as FrozenHelper

summaryCards : List { name : String } -> List (Html msg)
summaryCards users =
    users |> List.map (FrozenHelper.summaryCardWithPrefix "User: ")
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCardWithPrefix)

summaryCardWithPrefix prefix user =
    user
`
    );
    writeProjectFile(
      projectDir,
      "app/Route/Index.elm",
      `module Route.Index exposing (view)

import Ui.ListView as ListView

view users =
    ListView.summaryCards users
`
    );

    const issue = makeIssue(
      projectDir,
      "lib/Ui/ListView.elm",
      "FrozenHelper.summaryCardWithPrefix \"User: \""
    );
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "lib/Ui/FrozenHelper.elm",
      "lib/Ui/ListView.elm",
    ]);
  });

  it("keeps only issue file when unqualified import is ambiguous", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper exposing (summaryCard)
import Ui.OtherHelper exposing (summaryCard)

view users =
    users |> List.map summaryCard
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/OtherHelper.elm",
      `module Ui.OtherHelper exposing (summaryCard)

summaryCard user =
    user
`
    );

    const issue = makeIssue(projectDir, issuePath, "summaryCard");
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual(["app/Route/Index.elm"]);
  });

  it("prefers earlier source-directory when duplicate module paths exist", async () => {
    const projectDir = createTempProject(["app", "libA", "libB"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper as FrozenHelper

view users =
    users |> List.map FrozenHelper.summaryCard
`
    );
    writeProjectFile(
      projectDir,
      "libA/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );
    writeProjectFile(
      projectDir,
      "libB/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );

    const issue = makeIssue(
      projectDir,
      issuePath,
      "FrozenHelper.summaryCard"
    );
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "libA/Ui/FrozenHelper.elm",
    ]);
  });

  it("resolves helper path for parenthesized multiline references", async () => {
    const projectDir = createTempProject(["app", "lib"]);
    const issuePath = "app/Route/Index.elm";
    writeProjectFile(
      projectDir,
      issuePath,
      `module Route.Index exposing (view)

import Ui.FrozenHelper as FrozenHelper

view users =
    users |> List.map
        ( FrozenHelper.summaryCard
        )
`
    );
    writeProjectFile(
      projectDir,
      "lib/Ui/FrozenHelper.elm",
      `module Ui.FrozenHelper exposing (summaryCard)

summaryCard user =
    user
`
    );

    const issue = makeIssue(
      projectDir,
      issuePath,
      "( FrozenHelper.summaryCard\n        )"
    );
    const excluded = await __testHelpers.computeUnsupportedFixExclusionPaths(
      projectDir,
      [issue]
    );

    expect(excluded).toEqual([
      "app/Route/Index.elm",
      "lib/Ui/FrozenHelper.elm",
    ]);
  });
});
