/**
 * Test runner command - runs ProgramTest values headlessly via elm-test.
 *
 * Discovers ProgramTest values in test modules (same as test-view),
 * generates a TestRunner.elm that wraps each one with `done` and
 * `Test.test`, then runs elm-test with the lamdera compiler.
 *
 * Usage: elm-pages test-run
 *        elm-pages test-run tests/MyTests.elm
 *        elm-pages test-run --coverage
 */

import * as path from "node:path";
import * as fs from "node:fs";
import * as url from "node:url";
import { restoreColorSafe } from "../error-formatter.js";
import { resolveTestInputPath } from "../resolve-elm-module.js";
import {
  discoverProgramTestModules,
  findProgramTestValues,
  printCaughtError,
} from "./shared.js";
import { ensureDirSync, writeFileIfChanged } from "../file-helpers.js";
import { generate } from "../codegen.js";

export async function run(elmModulePath, options) {
  if (elmModulePath === "--help" || elmModulePath === "-h") {
    console.log(
      "Usage: elm-pages test-run [path-to-module]\n\n" +
        "Run page tests headlessly via elm-test.\n" +
        "Discovers ProgramTest values and runs them with `done`.\n\n" +
        "Options:\n" +
        "  --coverage                          Instrument sources and generate a coverage report\n" +
        "  --coverage-include <dir>            Only instrument these source directories (repeatable)\n" +
        "  --coverage-exclude <dir>            Exclude these source directories (repeatable)\n" +
        "  --coverage-include-module <pattern>  Only show these modules in the report (repeatable)\n" +
        "  --coverage-exclude-module <pattern>  Hide these modules from the report (repeatable)\n\n" +
        "Example:\n" +
        "  elm-pages test-run tests/FrameworkTests.elm\n" +
        "  elm-pages test-run --coverage\n" +
        "  elm-pages test-run  (auto-discovers test files in tests/)\n"
    );
    return;
  }

  try {
    // First, ensure generated code is up to date (including TestApp.elm)
    console.log("Generating elm-pages code...");
    await generate(".");

    let allTests = [];

    if (elmModulePath && elmModulePath !== "") {
      const resolved = await resolveTestInputPath(elmModulePath);
      const modName = resolved.moduleName;
      const filePath = path.join(
        resolved.sourceDirectory,
        modName.replace(/\./g, "/") + ".elm"
      );
      const values = findProgramTestValues(filePath);
      if (values.length > 0) {
        allTests.push({ moduleName: modName, values });
      }
    } else {
      allTests = discoverProgramTestModules().map(({ moduleName, values }) => ({
        moduleName,
        values,
      }));
    }

    if (allTests.length === 0) {
      console.error(
        "No ProgramTest values found.\n\n" +
          "Create a test module that exposes values with a ProgramTest type annotation:\n\n" +
          "    myTest : TestApp.ProgramTest\n" +
          "    myTest =\n" +
          '        TestApp.start "/" BackendTaskTest.init\n' +
          '            |> PagesProgram.ensureViewHas [ text "Hello" ]\n'
      );
      process.exit(1);
    }

    const totalValues = allTests.reduce((n, t) => n + t.values.length, 0);
    console.log(
      `Found ${totalValues} ProgramTest value${totalValues > 1 ? "s" : ""} in ${allTests.length} module${allTests.length > 1 ? "s" : ""}`
    );

    // Set up the build directory for the test runner.
    // We put the generated TestRunner.elm in the test-viewer directory
    // alongside the generated TestViewer.elm and TestApp.elm, and run
    // elm-test from a separate empty directory to avoid source-directory
    // overlap with elm-test's generated code.
    const testViewerDir = path.resolve(
      "elm-stuff/elm-pages/test-viewer"
    );
    const testRunDir = path.resolve(
      "elm-stuff/elm-pages/test-run"
    );
    ensureDirSync(testViewerDir);
    ensureDirSync(testRunDir);

    // ── Coverage: instrument sources ──
    const coverage = options.coverage;
    let coverageDataDir;
    let dirMapping;

    if (coverage) {
      const {
        getUserSourceDirs,
        instrumentSources,
        COVERAGE_ELM_STUB,
      } = await import("../coverage.js");

      const projectDirectory = path.resolve(".");
      const compileDir = path.resolve("elm-stuff/elm-pages");
      let userSourceDirs = await getUserSourceDirs(projectDirectory);

      // Apply --coverage-include / --coverage-exclude filters
      const include = options.coverageInclude || [];
      const exclude = options.coverageExclude || [];
      if (include.length > 0) {
        userSourceDirs = userSourceDirs.filter((d) =>
          include.some((inc) => path.normalize(d) === path.normalize(inc))
        );
      }
      if (exclude.length > 0) {
        userSourceDirs = userSourceDirs.filter((d) =>
          !exclude.some((exc) => path.normalize(d) === path.normalize(exc))
        );
      }

      if (userSourceDirs.length === 0) {
        console.warn("Warning: No user source directories found to instrument.");
      } else {
        const result = await instrumentSources(
          projectDirectory,
          userSourceDirs,
          compileDir
        );
        coverageDataDir = result.coverageDir;
        dirMapping = result.dirMapping;

        // Write Coverage.elm stub to test-viewer dir (accessible as a source dir)
        await writeFileIfChanged(
          path.join(testViewerDir, "Coverage.elm"),
          COVERAGE_ELM_STUB
        );
      }

      // Clean stale coverage output
      try {
        const staleLcov = path.join(process.cwd(), "coverage", "lcov.info");
        if (fs.existsSync(staleLcov)) fs.unlinkSync(staleLcov);
      } catch {}
    }

    // Generate the headless test runner module in the test-viewer dir
    // (where TestApp.elm also lives)
    const runnerModule = generateTestRunnerModule(allTests);
    await writeFileIfChanged(
      path.join(testViewerDir, "TestRunner.elm"),
      runnerModule
    );

    // Create elm.json in the test-run directory (where elm-test will run).
    // Source-directories point back to test-viewer (for TestRunner.elm,
    // TestApp.elm) and to the project's source directories.
    const elmJsonPath = path.resolve("elm.json");
    const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
    const testRunnerElmJson = { ...elmJson };
    const extraSourceDirectories = ["tests"];
    if (fs.existsSync(path.resolve("snapshot-tests/src"))) {
      extraSourceDirectories.push("snapshot-tests/src");
    }

    // Map source dirs: if coverage, remap instrumented dirs; otherwise use originals
    const mapSourceDir = (dir) => {
      if (coverage && dirMapping && dirMapping[dir] !== undefined) {
        return path.join("../coverage/instrumented", dirMapping[dir]);
      }
      return path.join("../../..", dir);
    };

    testRunnerElmJson["source-directories"] = elmJson["source-directories"]
      .filter((dir) => !dir.includes("elm-stuff/elm-pages/test-run"))
      .filter((dir) => !dir.includes("elm-stuff/elm-pages/test-viewer"))
      .map(mapSourceDir)
      .concat(
        extraSourceDirectories.map((dir) => path.join("../../..", dir)),
        ["../test-viewer"]
      );
    fs.writeFileSync(
      path.join(testRunDir, "elm.json"),
      JSON.stringify(testRunnerElmJson, null, 4)
    );

    // Detect compiler: prefer lamdera for Wire3 codecs
    const { execSync, spawnSync } = await import("node:child_process");
    let compiler = "elm";
    try {
      execSync("lamdera --help", { stdio: "ignore" });
      compiler = "lamdera";
    } catch (e) {
      // lamdera not available, use elm
    }

    // Coverage: create a compiler wrapper that injects tracking after compilation
    let compilerFlag = `--compiler=${compiler}`;
    if (coverage && coverageDataDir) {
      const wrapperPath = await createCompilerWrapper(compiler, coverageDataDir);
      compilerFlag = `--compiler=${wrapperPath}`;
    }

    console.log(`Running ${totalValues} test${totalValues > 1 ? "s" : ""}...\n`);

    // Run elm-test from the test-run directory.
    // TestRunner.elm is in ../test-viewer/ which is in source-directories.
    const result = spawnSync(
      "npx",
      [
        "elm-test",
        compilerFlag,
        "../test-viewer/TestRunner.elm",
      ],
      {
        stdio: "inherit",
        cwd: testRunDir,
      }
    );

    // ── Coverage: print report ──
    if (coverage && coverageDataDir) {
      const { printCoverageReportSync } = await import("../coverage.js");
      printCoverageReportSync(".", process.cwd(), {
        include: options.coverageIncludeModule || [],
        exclude: options.coverageExcludeModule || [],
      });
    }

    process.exit(result.status || 0);
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}

/**
 * Create a compiler wrapper script that calls the real compiler,
 * then injects coverage tracking into the compiled JS output.
 * elm-test calls this wrapper via --compiler=<path>.
 *
 * @param {string} compiler - Real compiler name ("elm" or "lamdera")
 * @param {string} coverageDataDir - Where coverage data files are written
 * @returns {Promise<string>} Path to the wrapper script
 */
async function createCompilerWrapper(compiler, coverageDataDir) {
  const coverageJsPath = path.resolve(
    path.dirname(url.fileURLToPath(import.meta.url)),
    "../coverage.js"
  );
  const coverageJsUrl = url.pathToFileURL(coverageJsPath).href;

  const wrapperDir = path.resolve("elm-stuff/elm-pages/coverage");
  ensureDirSync(wrapperDir);
  const wrapperPath = path.join(wrapperDir, "compiler-wrapper.mjs");

  const content = `#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { injectCoverageTracking } from ${JSON.stringify(coverageJsUrl)};

const compiler = ${JSON.stringify(compiler)};
const coverageDir = ${JSON.stringify(coverageDataDir)};
const args = process.argv.slice(2);

try {
  execFileSync(compiler, args, { stdio: "inherit" });
} catch (e) {
  process.exit(e.status || 1);
}

// Find --output file in compiler args
let outputFile;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--output" && i + 1 < args.length) {
    outputFile = args[i + 1];
  } else if (args[i].startsWith("--output=")) {
    outputFile = args[i].slice("--output=".length);
  }
}

if (outputFile) {
  await injectCoverageTracking(outputFile, coverageDir);
}
`;

  fs.writeFileSync(wrapperPath, content);
  fs.chmodSync(wrapperPath, 0o755);

  return wrapperPath;
}

/**
 * Generate the TestRunner.elm module that wraps ProgramTest values
 * with Test.test and PagesProgram.done for headless execution.
 */
function generateTestRunnerModule(allTests) {
  const imports = allTests
    .map((t) => `import ${t.moduleName}`)
    .join("\n");

  const testEntries = allTests
    .flatMap((t) =>
      t.values.map(
        (name) =>
          `        Test.test "${t.moduleName}.${name}" <|\n` +
          `            \\() ->\n` +
          `                ${t.moduleName}.${name}\n` +
          `                    |> Test.PagesProgram.done`
      )
    )
    .join("\n        , ");

  return `module TestRunner exposing (suite)

{-| Generated headless test runner. Do not edit manually.
Wraps each ProgramTest value with done to produce Test values,
so they can be run via elm-test.
-}

${imports}
import Test
import Test.PagesProgram


suite : Test.Test
suite =
    Test.describe "elm-pages ProgramTest"
        [ ${testEntries}
        ]
`;
}
