## Plan: `elm-pages run --coverage` Feature

### Overview

Add a `--coverage` flag to `elm-pages run` that instruments Elm source files, injects coverage tracking into the compiled JS, and generates an HTML coverage report after the script completes.

### Dependencies

- `elm-instrument` binary (from elm-coverage, installed via binwrap) — performs AST→AST transformation on .elm source files
- `elm-coverage`'s Elm analyzer (`src/Analyzer.elm` compiled to `lib/analyzer.js`) — generates HTML reports
- `elm-coverage`'s `aggregate.js`, `summarize.js`, `codeCov.js` — data aggregation and formatting

### Step 1: Add `--coverage` flag to CLI

In the elm-pages CLI definition (`cli.js` or equivalent), add a `--coverage` boolean option to the `run` command. Pass it through to the compilation/execution pipeline.

### Step 2: Instrument sources before compilation

When `--coverage` is enabled, before the normal compilation step:

1. Copy the script's source directories into a temp location (e.g. `.coverage/instrumented/`)
2. Run `elm-instrument` on the copied sources — this injects `Coverage.track "ModuleName" expressionIndex` calls into expression bodies (declarations, let-bindings, lambdas, if/else branches, case branches) and writes metadata to `.coverage/info.json`
3. Copy `Coverage.elm` stub into the instrumented source directory:
   ```elm
   module Coverage exposing (track)
   track : String -> Int -> ()
   track line index = ()
   ```
4. Modify the copied `elm.json` to set `"name": "author/project"` — this is required so the compiled JS function name is `$author$project$Coverage$track`, which the post-processor can find via regex

### Step 3: Point compilation at instrumented sources

Adjust the source directories passed to `lamdera make` so it compiles from `.coverage/instrumented/` instead of the original source. The generated `ScriptMain.elm` wrapper and all other elm-pages codegen should work as-is since module names haven't changed.

### Step 4: Post-process compiled JS to inject coverage tracking

After `lamdera make` produces the compiled JS (and after the existing `forceThunks` post-processing), inject coverage tracking code. Use the same regex pattern as elm-coverage's `fake-elm`:

```js
// Find the compiled Coverage.track function
const pattern = /(^var\s+\$author\$project\$Coverage\$track.*$\s+function\s+\()(\w+)\s*,\s*(\w+)\)\s+\{$/gm;

// Replace with counter-incrementing implementation + process exit dump
const replacement = `
var fs = require("fs");
var __coverage_counters = {};
process.on("beforeExit", function() {
    if (Object.keys(__coverage_counters).length > 0) {
        fs.writeFileSync(
            ".coverage/data-" + process.pid + ".json",
            JSON.stringify(__coverage_counters)
        );
    }
});

$1$2, $3) {
    __coverage_counters[$2] = __coverage_counters[$2] || [];
    __coverage_counters[$2].push($3);
`;
```

Key difference from elm-coverage: uses `process.on("beforeExit")` instead of subscribing to `elmTestPort__send`, since there's no elm-test — the script just runs and exits.

### Step 5: Run the script normally

The existing elm-pages script execution continues as-is. The injected code runs transparently — every time an instrumented expression is evaluated, the counter increments. When the Node process exits, counters are written to `.coverage/data-{pid}.json`.

### Step 6: Aggregate and generate report

After the script completes:

1. Read `.coverage/info.json` (instrumentation metadata from step 2)
2. Read all `.coverage/data-*.json` files (runtime counters from step 5)
3. Merge: for each module, match counter indices to annotation metadata, incrementing `count` on each annotation
4. Print a summary table to the console (reuse elm-coverage's `summarize.js` logic)
5. Generate HTML report at `.coverage/coverage.html` (reuse elm-coverage's Elm analyzer)

### Step 7: Cleanup

Touch original source files to reset timestamps (prevents unnecessary recompilation on next run without coverage). Optionally open the HTML report with `--open`.

### Architecture notes

- **elm-instrument** is a platform-specific binary distributed via binwrap. For elm-pages, it could be an optional dependency or downloaded on first use of `--coverage`.
- **The Elm analyzer** (`Analyzer.elm`) is pre-compiled to JS (`analyzer.js`). It's a `Platform.worker` that receives coverage data + source files via ports and returns generated HTML via a port. This can be vendored into elm-pages or kept as a dependency on elm-coverage.
- **Lamdera compatibility**: elm-instrument is a fork of elm-format's parser. Standard Elm syntax works fine. If Lamdera-specific syntax causes parse failures, those files could be skipped with a warning (coverage won't include them, but the build won't break).
- **The `author/project` naming convention**: This is the only "magic" string. The elm.json name must be set to this so the compiled JS uses `$author$project$Coverage$track` as the function name, which the regex can find. This is set on the temporary copy, not the user's real elm.json.

### Files to create/modify in elm-pages

| File | Change |
|---|---|
| `src/cli.js` | Add `--coverage` option to `run` command |
| `src/commands/run.js` | Orchestrate instrument → compile → inject → run → report |
| `src/coverage.js` (new) | Instrumentation, JS injection, aggregation, reporting logic |
| `package.json` | Add `elm-instrument` as optional dependency |

### What's reusable from elm-coverage as-is

- `elm-instrument` binary (AST transformation) — no changes
- `Coverage.elm` stub — no changes  
- `aggregate.js` logic — no changes
- `summarize.js` (console table) — no changes
- `Analyzer.elm` / `analyzer.js` (HTML report generation) — no changes
- `codeCov.js` (codecov format) — no changes

### What's new

- `process.on("beforeExit")` trigger instead of `elmTestPort__send` (~6 lines)
- CLI flag + orchestration wiring (~80 lines)
- Pointing compilation at instrumented sources (~30 lines)
