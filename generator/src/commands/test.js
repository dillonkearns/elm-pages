/**
 * Test command - unified entry point that auto-discovers and runs:
 *   - ProgramTest values (Test.PagesProgram)
 *   - TuiTest.Test / Test.Tui.Test values
 *   - Vanilla Test values (elm-explorations/test)
 *
 * Generates a per-module companion file under GeneratedTests/<Mod>.elm
 * that wraps each test type as a vanilla Test, plus a root
 * GeneratedTests/All.elm that aggregates them. Runs elm-test with the
 * lamdera compiler on the aggregated root. Replaces direct use of
 * `elm-test` for elm-pages projects.
 *
 * For the interactive TUI stepper over named TUI tests, use `--visual`.
 * For the browser-based visual stepper over ProgramTest values, run
 * `elm-pages dev` and open `/_tests`.
 *
 * Usage: elm-pages test
 *        elm-pages test tests/MyTests.elm
 *        elm-pages test --coverage
 *        elm-pages test --visual tests/MyTuiTest.elm
 */

import * as path from "node:path";
import * as fs from "node:fs";
import * as url from "node:url";
import { restoreColorSafe } from "../error-formatter.js";
import { resolveTestInputPath } from "../resolve-elm-module.js";
import {
  classifyAllTestValues,
  discoverAllTestModules,
  missingAnnotationsError,
  printCaughtError,
} from "./shared.js";
import { ensureDirSync, writeFileIfChanged } from "../file-helpers.js";
import { generate } from "../codegen.js";

export async function run(elmModulePath, options, options2) {
  if (elmModulePath === "--help" || elmModulePath === "-h") {
    console.log(
      "Usage: elm-pages test [path-to-module]\n\n" +
        "Auto-discover and run all test values via elm-test:\n" +
        "  - ProgramTest (Test.PagesProgram)\n" +
        "  - TuiTest.Test / Test.Tui.Test\n" +
        "  - Vanilla Test (elm-explorations/test)\n\n" +
        "Options:\n" +
        "  --visual                            Open named TUI tests in the interactive\n" +
        "                                        terminal stepper instead of running headlessly.\n" +
        "                                        For ProgramTest visual stepping, run\n" +
        "                                        `elm-pages dev` and open `/_tests`.\n" +
        "  --coverage                          Instrument sources and generate a coverage report\n" +
        "  --coverage-include <dir>            Only instrument these source directories (repeatable)\n" +
        "  --coverage-exclude <dir>            Exclude these source directories (repeatable)\n" +
        "  --coverage-include-module <pattern>  Only show these modules in the report (repeatable)\n" +
        "  --coverage-exclude-module <pattern>  Hide these modules from the report (repeatable)\n\n" +
        "Example:\n" +
        "  elm-pages test tests/FrameworkTests.elm\n" +
        "  elm-pages test --coverage\n" +
        "  elm-pages test  (auto-discovers test files in tests/)\n" +
        "  elm-pages test --visual tests/MyTuiTest.elm\n"
    );
    return;
  }

  if (options && options.visual) {
    const { run: runVisual } = await import("./test-visual.js");
    await runVisual(elmModulePath, options, options2);
    return;
  }

  try {
    let resolved = null;
    let projectDirectory = process.cwd();

    if (elmModulePath && elmModulePath !== "") {
      resolved = await resolveTestInputPath(elmModulePath);
      projectDirectory = resolved.projectDirectory;
      process.chdir(projectDirectory);
    }

    let allProgramTests = [];
    let allTuiTests = [];
    let allVanillaTests = [];
    /** @type {{file: string, moduleName: string, names: string[]}[]} */
    let missingAnnotations = [];

    if (resolved) {
      const modName = resolved.moduleName;
      const filePath = path.join(
        resolved.sourceDirectory,
        modName.replace(/\./g, "/") + ".elm"
      );
      const classified = await classifyAllTestValues(filePath);
      if (classified.program.length > 0) {
        allProgramTests.push({
          moduleName: modName,
          values: classified.program,
        });
      }
      if (classified.tui.length > 0) {
        allTuiTests.push({ moduleName: modName, values: classified.tui });
      }
      if (classified.vanilla.length > 0) {
        allVanillaTests.push({
          moduleName: modName,
          values: classified.vanilla,
        });
      }
      if (classified.missingAnnotation.length > 0) {
        missingAnnotations.push({
          file: filePath,
          moduleName: modName,
          names: classified.missingAnnotation,
        });
      }
    } else {
      const discovered = await discoverAllTestModules();
      allProgramTests = discovered.program.map(({ moduleName, values }) => ({
        moduleName,
        values,
      }));
      allTuiTests = discovered.tui.map(({ moduleName, values }) => ({
        moduleName,
        values,
      }));
      allVanillaTests = discovered.vanilla.map(({ moduleName, values }) => ({
        moduleName,
        values,
      }));
      missingAnnotations = discovered.missingAnnotations;
    }

    if (missingAnnotations.length > 0) {
      console.error(missingAnnotationsError(missingAnnotations));
      process.exit(1);
    }

    // Always regenerate elm-pages code — even vanilla Test modules may
    // import TestApp (e.g. for type annotations) or depend on generated
    // Pages.Db / Pages.DbSeed. Cheaper to always generate than to guess.
    console.log("Generating elm-pages code...");
    await generate(".");

    if (
      allProgramTests.length === 0 &&
      allTuiTests.length === 0 &&
      allVanillaTests.length === 0
    ) {
      console.error(
        "No test values found.\n\n" +
          "Expose values with one of these type annotations:\n\n" +
          "    myPageTest : TestApp.ProgramTest\n" +
          "    myPageTest =\n" +
          '        TestApp.start "/" BackendTaskTest.init\n' +
          '            |> PagesProgram.ensureViewHas [ text "Hello" ]\n\n' +
          "    myTuiTests : TuiTest.Test\n" +
          "    myTuiTests =\n" +
          '        TuiTest.describe "My TUI" [ TuiTest.test "works" <| ... ]\n\n' +
          "    mySuite : Test\n" +
          "    mySuite =\n" +
          '        Test.describe "plain tests" [ Test.test "works" <| \\() -> ... ]\n'
      );
      process.exit(1);
    }

    const totalProgramValues = allProgramTests.reduce((n, t) => n + t.values.length, 0);
    const totalTuiValues = allTuiTests.reduce((n, t) => n + t.values.length, 0);
    const totalVanillaValues = allVanillaTests.reduce((n, t) => n + t.values.length, 0);
    console.log(
      `Found ${totalProgramValues} ProgramTest value${totalProgramValues === 1 ? "" : "s"}, ${totalTuiValues} TUI test tree${totalTuiValues === 1 ? "" : "s"}, ${totalVanillaValues} plain Test value${totalVanillaValues === 1 ? "" : "s"}`
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

    // Generate per-module companion files under GeneratedTests/ plus a
    // root GeneratedTests.All that aggregates them. Each companion
    // converts ProgramTest/TuiTest values to vanilla Test values so
    // elm-test's own parser discovers them through `suite : Test`.
    const generatedDir = path.join(testViewerDir, "GeneratedTests");
    fs.rmSync(generatedDir, { recursive: true, force: true });
    // Remove the pre-restructure single-runner file if it lingers from an
    // older elm-pages test run — otherwise elm-test will try to compile
    // it and fail against stale user modules.
    const legacyRunner = path.join(testViewerDir, "TestRunner.elm");
    if (fs.existsSync(legacyRunner)) fs.unlinkSync(legacyRunner);

    const { companionModules, rootSource } = generateCompanionFiles(
      allProgramTests,
      allTuiTests,
      allVanillaTests
    );
    for (const m of companionModules) {
      const outPath = path.join(testViewerDir, m.companionPath);
      ensureDirSync(path.dirname(outPath));
      await writeFileIfChanged(outPath, m.source);
    }
    const rootPath = path.join(testViewerDir, "GeneratedTests", "All.elm");
    ensureDirSync(path.dirname(rootPath));
    await writeFileIfChanged(rootPath, rootSource);

    // Create elm.json in the test-run directory (where elm-test will run).
    // Source-directories point back to test-viewer (for TestRunner.elm,
    // TestApp.elm) and to the project's source directories.
    const elmJsonPath = path.resolve("elm.json");
    const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
    // Deep clone so we don't mutate the shared dependencies object.
    const testRunnerElmJson = JSON.parse(JSON.stringify(elmJson));
    const extraSourceDirectories = ["tests", "snapshot-tests/src"].filter((dir) =>
      fs.existsSync(path.join(projectDirectory, dir))
    );

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

    // Generated .elm-pages/Main.elm imports Lamdera.Wire3; make sure the
    // codecs package is available in the test-run compile even if the user's
    // elm.json doesn't list it (matches rewrite-elm-json.js behavior).
    testRunnerElmJson["dependencies"] = testRunnerElmJson["dependencies"] || {};
    testRunnerElmJson["dependencies"]["direct"] =
      testRunnerElmJson["dependencies"]["direct"] || {};
    testRunnerElmJson["dependencies"]["indirect"] =
      testRunnerElmJson["dependencies"]["indirect"] || {};
    const ensureDirectDep = (pkg, version) => {
      testRunnerElmJson["dependencies"]["direct"][pkg] = version;
      delete testRunnerElmJson["dependencies"]["indirect"][pkg];
    };
    ensureDirectDep("lamdera/codecs", "1.0.0");
    ensureDirectDep("elm/bytes", "1.0.8");

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

    const totalTopLevelEntries =
      totalProgramValues + totalTuiValues + totalVanillaValues;
    console.log(`Running ${totalTopLevelEntries} discovered test entr${totalTopLevelEntries === 1 ? "y" : "ies"}...\n`);

    // Run elm-test from the test-run directory.
    // GeneratedTests/All.elm is in ../test-viewer/ which is in source-directories.
    const result = spawnSync(
      "npx",
      [
        "elm-test",
        compilerFlag,
        "../test-viewer/GeneratedTests/All.elm",
      ],
      {
        stdio: "inherit",
        cwd: testRunDir,
      }
    );

    // ── Coverage: print report ──
    if (coverage && coverageDataDir) {
      const { printCoverageReportSync } = await import("../coverage.js");
      printCoverageReportSync(".", projectDirectory, {
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
 * Generate per-module companion files (one per user test module) plus a
 * root `GeneratedTests.All` that aggregates them.
 *
 * Each companion re-exposes the user module's tests as a single `suite :
 * Test`, applying `Test.PagesProgram.done` to ProgramTest values and
 * `Test.Tui.toTest` to TuiTest values. Vanilla Test values pass through
 * unchanged. The root runner `Test.describe`s the per-module suites.
 *
 * @returns {{
 *   companionModules: { companionName: string, companionPath: string, source: string }[],
 *   rootSource: string,
 * }}
 */
function generateCompanionFiles(programTests, tuiTests, vanillaTests) {
  const byModule = new Map();
  const ensure = (moduleName) => {
    if (!byModule.has(moduleName)) {
      byModule.set(moduleName, { program: [], tui: [], vanilla: [] });
    }
    return byModule.get(moduleName);
  };
  for (const t of programTests) ensure(t.moduleName).program = t.values;
  for (const t of tuiTests) ensure(t.moduleName).tui = t.values;
  for (const t of vanillaTests) ensure(t.moduleName).vanilla = t.values;

  const companionModules = [];
  for (const [userModule, { program, tui, vanilla }] of byModule) {
    const companionName = `GeneratedTests.${userModule}`;
    const companionPath =
      companionName.replace(/\./g, "/") + ".elm";
    const source = generateCompanionModule(
      companionName,
      userModule,
      program,
      tui,
      vanilla
    );
    companionModules.push({ companionName, companionPath, source });
  }

  return {
    companionModules,
    rootSource: generateRootRunner(companionModules),
  };
}

function generateCompanionModule(
  companionName,
  userModule,
  program,
  tui,
  vanilla
) {
  const entries = [];
  for (const name of program) {
    entries.push(
      `Test.test "${name}" <|\n` +
        `            \\() ->\n` +
        `                ${userModule}.${name}\n` +
        `                    |> Test.PagesProgram.done`
    );
  }
  for (const name of tui) {
    entries.push(
      `Test.describe "${name}"\n` +
        `            [ Test.Tui.toTest ${userModule}.${name} ]`
    );
  }
  for (const name of vanilla) {
    entries.push(
      `Test.describe "${name}"\n` + `            [ ${userModule}.${name} ]`
    );
  }

  const extraImports = [
    program.length > 0 ? "import Test.PagesProgram" : null,
    tui.length > 0 ? "import Test.Tui" : null,
  ]
    .filter(Boolean)
    .join("\n");

  return `module ${companionName} exposing (suite)

{-| Generated test wrapper for ${userModule}. Do not edit.
-}

import ${userModule}
import Test exposing (Test)
${extraImports ? extraImports + "\n" : ""}

suite : Test
suite =
    Test.describe "${userModule}"
        [ ${entries.join("\n        , ")}
        ]
`;
}

function generateRootRunner(companionModules) {
  const imports = companionModules
    .map((m) => `import ${m.companionName}`)
    .join("\n");
  const entries = companionModules
    .map((m) => `${m.companionName}.suite`)
    .join("\n        , ");

  return `module GeneratedTests.All exposing (suite)

{-| Aggregated elm-pages test runner. Do not edit manually.
Each import corresponds to a per-module companion that wraps the user's
tests as vanilla elm-explorations/test Test values.
-}

${imports}
import Test exposing (Test)


suite : Test
suite =
    Test.describe "elm-pages tests"
        [ ${entries}
        ]
`;
}
