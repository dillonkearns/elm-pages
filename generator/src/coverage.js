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

  // Include all user source dirs except .elm-pages (generated code).
  // Dirs like "../src" that go above the project root are still user code.
  return sourceDirs.filter((dir) => dir !== ".elm-pages");
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
  // Dirs may contain "../" so we flatten them to safe names inside instrumentedDir.
  const dirMapping = {}; // originalDir → instrumentedDirName
  const instrumentedSourceDirs = [];

  for (const srcDir of userSourceDirs) {
    const safeName = safeInstrumentedName(srcDir);
    dirMapping[srcDir] = safeName;
    instrumentedSourceDirs.push(safeName);

    if (srcDir === ".") {
      // "." means project root — only copy top-level .elm files
      const destDir = path.join(instrumentedDir, safeName);
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
      await copyDirectoryRecursive(
        path.resolve(projectDirectory, srcDir),
        path.join(instrumentedDir, safeName)
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

  // Save source directory info so the exit handler can resolve module → file paths
  const modulePaths = buildModulePathMap(projectDirectory, userSourceDirs);
  await fs.promises.writeFile(
    path.join(coverageDir, "module-paths.json"),
    JSON.stringify(modulePaths)
  );

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

  // Generate lcov.info at the conventional path: coverage/lcov.info
  try {
    let modulePaths = {};
    try {
      modulePaths = JSON.parse(
        fs.readFileSync(path.join(coverageDir, "module-paths.json"), "utf-8")
      );
    } catch {}
    const lcov = generateLcov(info, allCounters, projectDirectory, modulePaths);
    const lcovDir = path.join(projectDirectory, "coverage");
    try {
      fs.mkdirSync(lcovDir, { recursive: true });
    } catch {}
    const lcovPath = path.join(lcovDir, "lcov.info");
    fs.writeFileSync(lcovPath, lcov);
    console.log(`  Coverage report written to ${lcovPath}`);
  } catch (e) {
    console.warn("Warning: could not generate lcov.info:", e.message || e);
  }
}

// ─── Internal helpers ────────────────────────────────────────────

/**
 * Flatten a source directory path into a safe name for use inside
 * the instrumented directory. Replaces ".." with "_up" and "/" with "_".
 */
function safeInstrumentedName(dir) {
  if (dir === ".") return "root";
  return dir
    .split("/")
    .map((seg) => (seg === ".." ? "_up" : seg))
    .join("_");
}

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

  // elm-instrument writes to .coverage/info.json; create the directory and seed file
  const coverageMetaDir = path.join(instrumentedDir, ".coverage");
  await fs.promises.mkdir(coverageMetaDir, { recursive: true });
  await fs.promises.writeFile(
    path.join(coverageMetaDir, "info.json"),
    "{}"
  );

  // Call elm-instrument with "." to process ALL source files at once.
  // Passing individual files causes info.json to be overwritten per file.
  return new Promise((resolve, reject) => {
    const child = spawn("elm-instrument", ["."], {
      cwd: instrumentedDir,
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
          new Error(`elm-instrument exited with code ${code}\n${output}`)
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
 * Build a mapping from module names to their original source file paths
 * by scanning source directories for .elm files.
 */
function buildModulePathMap(projectDirectory, sourceDirs) {
  const map = {};
  for (const dir of sourceDirs) {
    if (dir === ".elm-pages") continue;
    const absDir = path.resolve(projectDirectory, dir);
    scanElmFilesSync(absDir, absDir, map);
  }
  return map;
}

function scanElmFilesSync(rootDir, dir, map) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      scanElmFilesSync(rootDir, full, map);
    } else if (entry.name.endsWith(".elm")) {
      const rel = path.relative(rootDir, full);
      const moduleName = rel.replace(/\.elm$/, "").split(path.sep).join(".");
      // First match wins (earlier source dirs take priority)
      if (!map[moduleName]) {
        map[moduleName] = full;
      }
    }
  }
}

/**
 * Generate lcov.info content from coverage metadata and runtime hits.
 * JS port of the TDD'd Elm logic in generator/lcov/src/Lcov.elm.
 *
 * @param {object} info - Module annotations from elm-instrument (info.json)
 * @param {object} allCounters - Merged runtime hit data { moduleName: [indices] }
 * @param {string} projectDirectory - For resolving module paths
 * @param {object} modulePaths - Module name → absolute file path mapping
 * @returns {string} lcov-formatted string
 */
function generateLcov(info, allCounters, projectDirectory, modulePaths) {
  const modules = info.modules || info;
  const sections = [];

  for (const [moduleName, annotations] of Object.entries(modules)) {
    const exprList = Array.isArray(annotations) ? annotations : [];
    const hits = allCounters[moduleName] || [];

    // Count hits per annotation index
    const hitCounts = new Map();
    for (const idx of hits) {
      hitCounts.set(idx, (hitCounts.get(idx) || 0) + 1);
    }

    // Resolve module name to file path using saved mapping
    const filePath = modulePaths[moduleName] || path.resolve(
      projectDirectory,
      moduleName.split(".").join("/") + ".elm"
    );

    const lines = ["TN:", `SF:${filePath}`];

    // Functions (declarations with names)
    const functions = [];
    for (let i = 0; i < exprList.length; i++) {
      const ann = exprList[i];
      if (ann.type === "declaration" && ann.name) {
        functions.push({ line: ann.from.line, name: ann.name, count: hitCounts.get(i) || 0 });
      }
    }
    for (const fn of functions) lines.push(`FN:${fn.line},${fn.name}`);
    for (const fn of functions) lines.push(`FNDA:${fn.count},${fn.name}`);
    if (functions.length > 0) {
      lines.push(`FNF:${functions.length}`);
      lines.push(`FNH:${functions.filter((f) => f.count > 0).length}`);
    }

    // Branches (caseBranch, ifElseBranch)
    const branches = [];
    for (let i = 0; i < exprList.length; i++) {
      const ann = exprList[i];
      if (ann.type === "caseBranch" || ann.type === "ifElseBranch") {
        branches.push({ line: ann.from.line, count: hitCounts.get(i) || 0 });
      }
    }
    branches.forEach((br, idx) => lines.push(`BRDA:${br.line},0,${idx},${br.count}`));
    if (branches.length > 0) {
      lines.push(`BRF:${branches.length}`);
      lines.push(`BRH:${branches.filter((b) => b.count > 0).length}`);
    }

    // Line data — expand each annotation to its full line range.
    // When annotations overlap, the innermost (smallest range) wins.
    const annsWithCounts = exprList.map((ann, i) => ({
      startLine: ann.from.line,
      endLine: ann.to.line,
      count: hitCounts.get(i) || 0,
      range: ann.to.line - ann.from.line,
    }));

    const allLines = new Set();
    for (const a of annsWithCounts) {
      for (let l = a.startLine; l <= a.endLine; l++) allLines.add(l);
    }
    const sortedLines = [...allLines].sort((a, b) => a - b);

    let lh = 0;
    for (const line of sortedLines) {
      // Find innermost annotation covering this line
      let best = null;
      for (const a of annsWithCounts) {
        if (a.startLine <= line && line <= a.endLine) {
          if (!best || a.range < best.range) best = a;
        }
      }
      const count = best ? best.count : 0;
      lines.push(`DA:${line},${count}`);
      if (count > 0) lh++;
    }
    lines.push(`LF:${sortedLines.length}`);
    lines.push(`LH:${lh}`);
    lines.push("end_of_record");
    lines.push("");

    sections.push(lines.join("\n"));
  }

  return sections.join("\n");
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
