/**
 * Coverage instrumentation and reporting for elm-pages scripts.
 *
 * Flow:
 * 1. Copy user source dirs to .coverage/instrumented/
 * 2. Run elm-instrument on the copies (instruments in place, writes metadata)
 * 3. Write Coverage.elm stub to compilation .elm-pages/ dir
 * 4. Modify compilation elm.json to point to instrumented sources
 * 5. After compile: inject JS tracking code into compiled output
 * 6. After run: read coverage data, generate report
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { spawn } from "cross-spawn";

const COVERAGE_DIR = ".coverage";

/**
 * Get user source directories from elm.json that should be instrumented.
 * Filters out directories outside the project root and .elm-pages (generated code).
 *
 * @param {string} projectDirectory
 * @returns {Promise<string[]>} source dir paths relative to projectDirectory
 */
export async function getUserSourceDirs(projectDirectory) {
  const elmJsonPath = path.join(projectDirectory, "elm.json");
  const elmJson = JSON.parse(await fs.promises.readFile(elmJsonPath, "utf-8"));
  const sourceDirs = elmJson["source-directories"] || [];
  const projectRoot = path.resolve(projectDirectory);

  return sourceDirs.filter((dir) => {
    if (dir === ".elm-pages") return false;
    const resolved = path.resolve(projectDirectory, dir);
    return resolved.startsWith(projectRoot);
  });
}

/**
 * Set up coverage instrumentation before compilation.
 *
 * @param {string} projectDirectory - The script's project directory
 * @param {string[]} userSourceDirs - Source dirs to instrument (relative to projectDirectory)
 * @param {string} compileDir - Compilation directory (elm-stuff/elm-pages)
 * @returns {Promise<{coverageDir: string, dirMapping: Record<string,string>}>}
 */
export async function setupCoverage(
  projectDirectory,
  userSourceDirs,
  compileDir
) {
  const coverageDir = path.join(projectDirectory, COVERAGE_DIR);
  const instrumentedDir = path.join(coverageDir, "instrumented");

  // Clean previous coverage data
  await fs.promises.rm(coverageDir, { recursive: true, force: true });
  await fs.promises.mkdir(instrumentedDir, { recursive: true });

  // Copy source dirs to instrumented location.
  // "." is special: only copy top-level .elm files → "root/" subdirectory.
  const dirMapping = {}; // originalDir → instrumentedDirName
  const instrumentedSourceDirs = [];

  for (const srcDir of userSourceDirs) {
    if (srcDir === ".") {
      const name = "root";
      dirMapping["."] = name;
      instrumentedSourceDirs.push(name);
      const destDir = path.join(instrumentedDir, name);
      await fs.promises.mkdir(destDir, { recursive: true });
      const entries = await fs.promises.readdir(projectDirectory);
      for (const entry of entries) {
        if (entry.endsWith(".elm")) {
          await fs.promises.copyFile(
            path.join(projectDirectory, entry),
            path.join(destDir, entry)
          );
        }
      }
    } else {
      dirMapping[srcDir] = srcDir;
      instrumentedSourceDirs.push(srcDir);
      await copyDirectoryRecursive(
        path.resolve(projectDirectory, srcDir),
        path.join(instrumentedDir, srcDir)
      );
    }
  }

  // Run elm-instrument
  await runElmInstrument(projectDirectory, instrumentedDir, instrumentedSourceDirs);

  // Write Coverage.elm stub into the compile dir's .elm-pages/ (already a source dir)
  await fs.promises.writeFile(
    path.join(compileDir, ".elm-pages", "Coverage.elm"),
    COVERAGE_ELM_STUB
  );

  // Redirect compile elm.json source dirs to instrumented copies
  await rewriteElmJsonForCoverage(compileDir, dirMapping);

  return { coverageDir, dirMapping };
}

/**
 * Inject coverage tracking into the compiled JS file.
 * Replaces the no-op Coverage.track with counter-incrementing code
 * and a beforeExit handler that writes data to disk.
 *
 * @param {string} jsFilePath - Path to the compiled .cjs file
 * @param {string} coverageDataDir - Absolute path where data-*.json files are written
 */
export async function injectCoverageTracking(jsFilePath, coverageDataDir) {
  let js = await fs.promises.readFile(jsFilePath, "utf-8");

  // Elm 0.19 compiles a 2-arg function as:
  //   var $author$project$Coverage$track = F2(function(a, b) { return 0; });
  const pattern =
    /var \$author\$project\$Coverage\$track\s*=\s*F2\(\s*function\s*\((\w+),\s*(\w+)\)\s*\{[^}]*\}\s*\)/;

  const match = js.match(pattern);
  if (!match) {
    console.warn(
      "Warning: Could not find $author$project$Coverage$track in compiled output.\n" +
        "Coverage data will not be collected."
    );
    return;
  }

  const [fullMatch, arg1, arg2] = match;
  const dir = JSON.stringify(coverageDataDir.replace(/\\/g, "/"));

  const replacement = `var __coverage_fs = require("fs");
var __coverage_path = require("path");
var __coverage_counters = {};
process.on("exit", function() {
    if (Object.keys(__coverage_counters).length > 0) {
        try { __coverage_fs.mkdirSync(${dir}, { recursive: true }); } catch(e) {}
        __coverage_fs.writeFileSync(
            __coverage_path.join(${dir}, "data-" + process.pid + ".json"),
            JSON.stringify(__coverage_counters)
        );
    }
});
var $author$project$Coverage$track = F2(function(${arg1}, ${arg2}) {
    __coverage_counters[${arg1}] = __coverage_counters[${arg1}] || [];
    __coverage_counters[${arg1}].push(${arg2});
    return 0;
})`;

  js = js.replace(fullMatch, replacement);
  await fs.promises.writeFile(jsFilePath, js);
}

/**
 * Synchronous coverage report for use in a process "exit" handler.
 * Must be synchronous because async code cannot run in "exit" handlers,
 * and elm-pages scripts call process.exit(0) on completion.
 *
 * @param {string} projectDirectory
 */
export function printCoverageReportSync(projectDirectory) {
  const coverageDir = path.join(projectDirectory, COVERAGE_DIR);

  // Read instrumentation metadata
  const infoPath = path.join(
    coverageDir, "instrumented", ".coverage", "info.json"
  );
  let info;
  try {
    info = JSON.parse(fs.readFileSync(infoPath, "utf-8"));
  } catch {
    console.warn("No coverage metadata found at", infoPath);
    return;
  }

  // Read runtime data files (written by the earlier exit handler)
  let entries;
  try {
    entries = fs.readdirSync(coverageDir);
  } catch {
    return;
  }
  const dataFiles = entries.filter(
    (f) => f.startsWith("data-") && f.endsWith(".json")
  );

  if (dataFiles.length === 0) {
    console.warn("No coverage data collected. Did the script execute?");
    return;
  }

  // Merge all data files
  const allCounters = {};
  for (const file of dataFiles) {
    const data = JSON.parse(
      fs.readFileSync(path.join(coverageDir, file), "utf-8")
    );
    for (const [mod, indices] of Object.entries(data)) {
      if (!allCounters[mod]) allCounters[mod] = [];
      allCounters[mod].push(...indices);
    }
  }

  const summary = computeSummary(info, allCounters);
  printSummary(summary);
}

// ─── Internal helpers ────────────────────────────────────────────

async function rewriteElmJsonForCoverage(compileDir, dirMapping) {
  const elmJsonPath = path.join(compileDir, "elm.json");
  const elmJson = JSON.parse(await fs.promises.readFile(elmJsonPath, "utf-8"));
  const pfx = "../../";

  elmJson["source-directories"] = elmJson["source-directories"].map((dir) => {
    if (dir === ".elm-pages") return dir;

    // parentDirectory corresponds to original source dir "."
    if (dir === "parentDirectory" && dirMapping["."]) {
      return `${pfx}${COVERAGE_DIR}/instrumented/${dirMapping["."]}`;
    }

    // Standard dirs: "../../<origDir>" → "../../.coverage/instrumented/<origDir>"
    if (dir.startsWith(pfx)) {
      const original = dir.slice(pfx.length);
      if (dirMapping[original] !== undefined) {
        return `${pfx}${COVERAGE_DIR}/instrumented/${dirMapping[original]}`;
      }
    }

    return dir; // non-user dirs (library sources) stay unchanged
  });

  await fs.promises.writeFile(elmJsonPath, JSON.stringify(elmJson));
}

async function runElmInstrument(
  projectDirectory,
  instrumentedDir,
  sourceDirs
) {
  // Create an elm.json for elm-instrument with the instrumented source dirs
  const originalElmJson = JSON.parse(
    await fs.promises.readFile(
      path.join(projectDirectory, "elm.json"),
      "utf-8"
    )
  );
  await fs.promises.writeFile(
    path.join(instrumentedDir, "elm.json"),
    JSON.stringify(
      { ...originalElmJson, "source-directories": sourceDirs },
      null,
      4
    )
  );

  // elm-instrument appends to .coverage/info.json; create the directory and seed file
  const coverageMetaDir = path.join(instrumentedDir, ".coverage");
  await fs.promises.mkdir(coverageMetaDir, { recursive: true });
  await fs.promises.writeFile(
    path.join(coverageMetaDir, "info.json"),
    "{}"
  );

  // Find all .elm files in the source directories
  const elmFiles = [];
  for (const srcDir of sourceDirs) {
    const absDir = path.join(instrumentedDir, srcDir);
    await collectElmFiles(instrumentedDir, absDir, elmFiles);
  }

  // elm-instrument takes one file at a time as [INPUT]
  for (const file of elmFiles) {
    await instrumentOneFile(instrumentedDir, file);
  }
}

async function collectElmFiles(rootDir, dir, result) {
  const entries = await fs.promises.readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await collectElmFiles(rootDir, full, result);
    } else if (entry.name.endsWith(".elm")) {
      // Path relative to instrumentedDir (elm-instrument's cwd)
      result.push(path.relative(rootDir, full));
    }
  }
}

function instrumentOneFile(cwd, relativeElmPath) {
  return new Promise((resolve, reject) => {
    const child = spawn("elm-instrument", [relativeElmPath], {
      cwd,
      stdio: "pipe",
    });

    let output = "";
    child.stdout?.on("data", (d) => {
      output += d;
    });
    child.stderr?.on("data", (d) => {
      output += d;
    });

    child.on("error", (err) => {
      if (err.code === "ENOENT") {
        reject(
          new Error(
            "elm-instrument not found.\n" +
              "Install elm-coverage which includes it:\n" +
              "  npm install -g elm-coverage"
          )
        );
      } else {
        reject(new Error(`elm-instrument failed: ${err.message}\n${output}`));
      }
    });

    child.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(
          new Error(
            `elm-instrument failed on ${relativeElmPath} (exit ${code})\n${output}`
          )
        );
      }
    });
  });
}

async function copyDirectoryRecursive(src, dest) {
  await fs.promises.mkdir(dest, { recursive: true });
  const entries = await fs.promises.readdir(src, { withFileTypes: true });
  for (const entry of entries) {
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      await copyDirectoryRecursive(s, d);
    } else {
      await fs.promises.copyFile(s, d);
    }
  }
}

function computeSummary(info, allCounters) {
  const summary = {};
  // elm-instrument writes { "modules": { "Mod": [ {annotation, count}, ... ] } }
  // or sometimes just { "Mod": [...] }
  const modules = info.modules || info;

  for (const [moduleName, expressions] of Object.entries(modules)) {
    const exprList = Array.isArray(expressions) ? expressions : [];
    const total = exprList.length;
    const hitSet = new Set(allCounters[moduleName] || []);
    const covered = hitSet.size;
    const percentage = total > 0 ? (covered / total) * 100 : 100;
    summary[moduleName] = { total, covered, percentage };
  }

  return summary;
}

function printSummary(summary) {
  const modules = Object.entries(summary).sort(([a], [b]) =>
    a.localeCompare(b)
  );

  if (modules.length === 0) {
    console.log("\nNo coverage data to report.");
    return;
  }

  console.log("\n── Coverage Report ──────────────────────────────────────");
  console.log("");

  const maxLen = Math.max(...modules.map(([n]) => n.length), 6);
  const header = `  ${"Module".padEnd(maxLen)}  ${"Covered".padStart(8)}  ${"Total".padStart(6)}  ${"Coverage".padStart(9)}`;
  const rule = "  " + "─".repeat(maxLen + 28);

  console.log(header);
  console.log(rule);

  let totalCovered = 0;
  let totalAll = 0;

  for (const [name, d] of modules) {
    const pct = `${d.percentage.toFixed(1)}%`;
    const c =
      d.percentage >= 80 ? "\x1b[32m" : d.percentage >= 50 ? "\x1b[33m" : "\x1b[31m";
    console.log(
      `  ${name.padEnd(maxLen)}  ${String(d.covered).padStart(8)}  ${String(d.total).padStart(6)}  ${c}${pct.padStart(9)}\x1b[0m`
    );
    totalCovered += d.covered;
    totalAll += d.total;
  }

  const overallPct =
    totalAll > 0 ? ((totalCovered / totalAll) * 100).toFixed(1) : "100.0";
  const oc =
    parseFloat(overallPct) >= 80
      ? "\x1b[32m"
      : parseFloat(overallPct) >= 50
        ? "\x1b[33m"
        : "\x1b[31m";

  console.log(rule);
  console.log(
    `  ${"TOTAL".padEnd(maxLen)}  ${String(totalCovered).padStart(8)}  ${String(totalAll).padStart(6)}  ${oc}${(overallPct + "%").padStart(9)}\x1b[0m`
  );
  console.log("");
}

/**
 * Coverage.elm stub. When compiled, produces $author$project$Coverage$track
 * which the JS post-processor replaces with actual tracking code.
 */
const COVERAGE_ELM_STUB = `module Coverage exposing (track)


track : String -> Int -> ()
track moduleName index =
    ()
`;
