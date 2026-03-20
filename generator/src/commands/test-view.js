/**
 * Test viewer command - compiles page tests into a browser-based visual stepper.
 *
 * Discovers ProgramTest values in the given module, generates a viewer app
 * that wraps them with Test.PagesProgram.Viewer.app, compiles to HTML,
 * and opens in the browser.
 *
 * Usage: elm-pages test-view tests/MyPageTests.elm
 *        elm-pages test-view  (auto-discovers test files)
 */

import * as path from "node:path";
import * as fs from "node:fs";
import * as globby from "globby";
import { restoreColorSafe } from "../error-formatter.js";
import {
  resolveTestInputPath,
} from "../resolve-elm-module.js";
import { printCaughtError, findProgramTestValues } from "./shared.js";
import {
  ensureDirSync,
  writeFileIfChanged,
} from "../file-helpers.js";
import { generate } from "../codegen.js";

export async function run(elmModulePath, options) {
  if (elmModulePath === "--help" || elmModulePath === "-h") {
    console.log(
      "Usage: elm-pages test-view [path-to-module]\n\n" +
        "Open page tests in the browser-based visual stepper.\n" +
        "The module must expose values with a ProgramTest type annotation.\n\n" +
        "Example:\n" +
        "  elm-pages test-view tests/MyPageTests.elm\n" +
        "  elm-pages test-view  (auto-discovers test files in tests/)\n"
    );
    return;
  }

  try {
    // First, ensure generated code is up to date (including TestApp.elm)
    console.log("Generating elm-pages code...");
    await generate(".");

    let moduleName, sourceDirectory, projectDirectory;

    if (elmModulePath && elmModulePath !== "") {
      const resolved = await resolveTestInputPath(elmModulePath);
      moduleName = resolved.moduleName;
      sourceDirectory = resolved.sourceDirectory;
      projectDirectory = resolved.projectDirectory;
    } else {
      // Auto-discover test files
      const testFiles = globby.globbySync(["tests/**/*.elm"]);
      const candidates = [];

      for (const file of testFiles) {
        const values = findProgramTestValues(file);
        if (values.length > 0) {
          const relPath = path.relative("tests", file);
          const modName = relPath
            .replace(/\.elm$/, "")
            .replace(/\//g, ".")
            .replace(/\\/g, ".");
          candidates.push({ moduleName: modName, file, values });
        }
      }

      if (candidates.length === 0) {
        console.error(
          "No ProgramTest values found in tests/.\n\n" +
            "Create a test module that exposes values with a ProgramTest type annotation:\n\n" +
            "    myTest : ProgramTest Model Msg\n" +
            "    myTest =\n" +
            '        PagesProgram.start (TestApp.index {})\n' +
            '            |> PagesProgram.ensureViewHas [ text "Hello" ]\n'
        );
        process.exit(1);
      }

      // Use all discovered test modules
      moduleName = candidates.map((c) => c.moduleName);
      sourceDirectory = "tests";
      projectDirectory = ".";
    }

    // If moduleName is a string (single file), find test values in it
    const modules = Array.isArray(moduleName) ? moduleName : [moduleName];
    const allTests = [];

    for (const mod of modules) {
      const filePath = Array.isArray(moduleName)
        ? path.join("tests", mod.replace(/\./g, "/") + ".elm")
        : path.join(
            sourceDirectory || ".",
            mod.replace(/\./g, "/") + ".elm"
          );

      const values = findProgramTestValues(filePath);
      if (values.length > 0) {
        allTests.push({ moduleName: mod, values });
      }
    }

    if (allTests.length === 0) {
      console.error(
        `No ProgramTest values found.\n\n` +
          "Expose values with a ProgramTest type annotation in your test module."
      );
      process.exit(1);
    }

    const totalValues = allTests.reduce((n, t) => n + t.values.length, 0);
    console.log(
      `Found ${totalValues} ProgramTest value${totalValues > 1 ? "s" : ""} in ${allTests.length} module${allTests.length > 1 ? "s" : ""}`
    );

    // Generate viewer wrapper module
    const viewerModule = generateViewerModule(allTests);
    const viewerDir = path.resolve(".elm-pages");
    ensureDirSync(viewerDir);
    await writeFileIfChanged(
      path.join(viewerDir, "TestViewer.elm"),
      viewerModule
    );

    // Compile to HTML
    // Temporarily add tests/ to source-directories so elm can find test modules
    const outputPath = path.resolve("tests/viewer.html");
    ensureDirSync(path.dirname(outputPath));

    console.log("Compiling test viewer...");

    const elmJsonPath = path.resolve(projectDirectory || ".", "elm.json");
    const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
    const originalSourceDirs = [...elmJson["source-directories"]];

    // Add tests/ if not already present
    if (!elmJson["source-directories"].includes("tests")) {
      elmJson["source-directories"].push("tests");
      fs.writeFileSync(elmJsonPath, JSON.stringify(elmJson, null, 4));
    }

    const { spawnSync } = await import("node:child_process");
    const elmBinary = "elm";

    const result = spawnSync(
      elmBinary,
      [
        "make",
        path.join(viewerDir, "TestViewer.elm"),
        `--output=${outputPath}`,
        "--debug",
      ],
      {
        stdio: "inherit",
        cwd: projectDirectory || ".",
      }
    );

    // Restore original source-directories
    elmJson["source-directories"] = originalSourceDirs;
    fs.writeFileSync(elmJsonPath, JSON.stringify(elmJson, null, 4));

    if (result.status !== 0) {
      console.error("Failed to compile test viewer.");
      process.exit(1);
    }

    console.log(`\nViewer compiled to: ${outputPath}`);

    // Open in browser
    const { exec } = await import("node:child_process");
    const openCmd =
      process.platform === "darwin"
        ? "open"
        : process.platform === "win32"
          ? "start"
          : "xdg-open";

    exec(`${openCmd} ${outputPath}`, (err) => {
      if (err) {
        console.log(`Open ${outputPath} in your browser to view tests.`);
      }
    });
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}

/**
 * Generate the TestViewer.elm module that wraps discovered ProgramTest values
 * with the visual stepper.
 */
function generateViewerModule(allTests) {
  const imports = allTests
    .map((t) => `import ${t.moduleName}`)
    .join("\n");

  const testEntries = allTests
    .flatMap((t) =>
      t.values.map(
        (name) =>
          `        ( "${t.moduleName}.${name}"\n` +
          `        , Test.PagesProgram.toSnapshots ${t.moduleName}.${name}\n` +
          `        )`
      )
    )
    .join("\n        , ");

  return `module TestViewer exposing (main)

{-| Generated test viewer. Do not edit manually.
Compile with: elm make .elm-pages/TestViewer.elm --output=tests/viewer.html
-}

${imports}
import Test.PagesProgram
import Test.PagesProgram.Viewer as Viewer


main : Program Viewer.Flags Viewer.Model Viewer.Msg
main =
    Viewer.app
        [ ${testEntries}
        ]
`;
}
