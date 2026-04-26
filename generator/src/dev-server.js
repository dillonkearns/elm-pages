import * as path from "path";
import * as fs from "fs";
import { default as which } from "which";
import * as chokidar from "chokidar";
import { URL } from "url";
import {
  compileElmForBrowser,
  runElmReview,
  compileCliApp,
} from "./compile-elm.js";
import * as http from "http";
import * as https from "https";
import * as codegen from "./codegen.js";
import * as kleur from "kleur/colors";
import { default as serveStatic } from "serve-static";
import { default as mimeTypes } from "mime-types";
import { default as connect } from "connect";
import { restoreColorSafe } from "./error-formatter.js";
import { Worker, SHARE_ENV } from "worker_threads";
import * as os from "os";
import { ensureDirSync } from "./file-helpers.js";
import { baseMiddleware } from "./basepath-middleware.js";
import * as devcert from "devcert";
import * as busboy from "busboy";
import { createServer as createViteServer } from "vite";
import * as esbuild from "esbuild";
import { merge_vite_configs } from "./vite-utils.js";
import { templateHtml } from "./pre-render-html.js";
import { resolveConfig } from "./config.js";
import { extractAndReplaceFrozenViews, replaceFrozenViewPlaceholders } from "./extract-frozen-views.js";
import { packageVersion } from "./compatibility-key.js";
import { toExactBuffer } from "./binary-helpers.js";
import * as globby from "globby";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * @param {{ port: string; base: string; https: boolean; debug: boolean; }} options
 */
export async function start(options) {
  console.error = function (...messages) {
    if (
      messages &&
      messages[0] &&
      !(
        typeof messages[0] === "string" &&
        messages[0].startsWith("Failed to load url")
      )
    ) {
      console.info(...messages);
    }
  };

  let threadReadyQueue = [];
  let pool = [];

  function invalidatePool() {
    pool.forEach((thread) => {
      if (thread.used) {
        thread.stale = true;
      }
    });
    restartIdleWorkersIfStale();
  }

  function restartIdleWorkersIfStale() {
    pool.forEach((thread) => {
      if (thread.stale && thread.ready) {
        reinitThread(thread);
      }
    });
  }

  function reinitThread(thisThread) {
    thisThread.worker && thisThread.worker.terminate();
    // TODO remove event listeners to avoid memory leak?
    // thread.worker.removeAllListeners("message");
    // thread.worker.removeAllListeners("error");
    thisThread.ready = false;
    thisThread.stale = false;
    thisThread.used = false;
    thisThread.worker = new Worker(path.join(__dirname, "./render-worker.js"), {
      env: SHARE_ENV,
      workerData: { basePath: options.base },
    });
    thisThread.worker.once("online", () => {
      thisThread.ready = true;
    });
  }

  ensureDirSync(path.join(process.cwd(), ".elm-pages", "http-response-cache"));
  const cpuCount = os.cpus().length;

  const port = options.port;
  const useHttps = options.https;
  let elmMakeRunning = true;

  fs.mkdirSync(".elm-pages/cache", { recursive: true });
  const serveCachedFiles = serveStatic(".elm-pages/cache", { index: false });
  const generatedFilesDirectory = "elm-stuff/elm-pages/generated-files";
  fs.mkdirSync(generatedFilesDirectory, { recursive: true });

  const serveStaticCode = serveStatic(
    path.join(__dirname, "../static-code"),
    {}
  );
  /** @type {{ id: number, response: http.ServerResponse }[]} */
  let clients = [];

  // TODO check source-directories for what to watch?
  const watcher = chokidar.watch(["elm.json"], {
    persistent: true,
    ignored: [/\.swp$/],
    ignoreInitial: true,
  });

  // Run independent startup tasks in parallel
  let config;
  try {
    const results = await Promise.all([
      codegen.generate(options.base),
      ensureRequiredExecutables(),
      resolveConfig(),
    ]);
    config = results[2];
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
  let clientElmMakeProcess = compileElmForBrowser(options, config);
  let pendingCliCompile = compileCliApp(
    options,
    ".elm-pages/Main.elm",

    path.join(process.cwd(), "elm-stuff/elm-pages/", "elm.js"),

    // "elm.js",
    "elm-stuff/elm-pages/",
    path.join("elm-stuff/elm-pages/", "elm.js")
  );

  watchElmSourceDirs(true);

  async function setup() {
    await Promise.all([clientElmMakeProcess, pendingCliCompile])
      .then(() => {
        elmMakeRunning = false;
      })
      .catch(() => {
        elmMakeRunning = false;
      });
    console.log(
      `${kleur.dim(`elm-pages dev server running at`)} ${kleur.green(
        `<${useHttps ? "https" : "http"}://localhost:${port}>`
      )}`
    );
    const poolSize = Math.max(1, cpuCount / 2 - 1);
    for (let index = 0; index < poolSize; index++) {
      pool.push(initWorker(options.base));
    }
    runPendingWork();
  }

  setup();

  /**
   * @param {boolean} initialRun
   */
  async function watchElmSourceDirs(initialRun) {
    if (initialRun) {
    } else {
      console.log("elm.json changed - reloading watchers");
      watcher.removeAllListeners();
    }
    const sourceDirs = JSON.parse(
      (await fs.promises.readFile("./elm.json")).toString()
    )["source-directories"].filter(
      (sourceDir) => path.resolve(sourceDir) !== path.resolve(".elm-pages")
    );

    watcher.add(sourceDirs);

    // Also watch tests/ for test viewer live reload
    if (fs.existsSync("tests")) {
      watcher.add("tests");
    }
  }

  const app = connect();
  let httpServer;
  if (useHttps) {
    const ssl = await devcert.certificateFor("localhost");
    httpServer = https.createServer(ssl, app);
  } else {
    httpServer = http.createServer(app);
  }

  const vite = await createViteServer(
    merge_vite_configs(
      {
        server: {
          middlewareMode: true,
          hmr: {
            server: httpServer,
          },
          base: options.base,
          port: options.port,
        },
        assetsInclude: ["/elm-pages.js"],
        appType: "custom",
        configFile: false,
        root: process.cwd(),
        base: options.base,
        /*
        Using explicit optimizeDeps.include prevents the following Vite warning message:
        (!) Could not auto-determine entry point from rollupOptions or html files and there are no explicit optimizeDeps.include patterns. Skipping dependency pre-bundling.
         */
        optimizeDeps: {
          include: [],
        },
      },

      config.vite
    )
  );

  const ctx = await esbuild.context({
    entryPoints: ["./custom-backend-task"],
    platform: "node",
    assetNames: "[name]-[hash]",
    chunkNames: "chunks/[name]-[hash]",
    outExtension: { ".js": ".mjs" },
    format: "esm",
    metafile: true,
    bundle: true,
    packages: "external",
    logLevel: "silent",
    outdir: ".elm-pages/compiled-ports",
    entryNames: "[dir]/[name]-[hash]",

    plugins: [
      {
        name: "example",
        setup(build) {
          build.onEnd(async (result) => {
            try {
              global.portsFilePath = Object.keys(result.metafile.outputs)[0];

              clients.forEach((client) => {
                client.response.write(`data: content.dat\n\n`);
              });
            } catch (e) {
              const portBackendTaskFileFound =
                globby.globbySync("./custom-backend-task.*").length > 0;
              if (portBackendTaskFileFound) {
                // don't present error if there are no files matching custom-backend-task
                // if there are files matching custom-backend-task, warn the user in case something went wrong loading it
                const messages = (
                  await esbuild.formatMessages(result.errors, {
                    kind: "error",
                    color: true,
                  })
                ).join("\n");
                global.portsFilePath = {
                  __internalElmPagesError: messages,
                };

                clients.forEach((client) => {
                  client.response.write(`data: content.dat\n\n`);
                });
              } else {
                global.portsFilePath = null;
              }
            }
          });
        },
      },
    ],
  });
  await ctx.watch();

  app
    .use(timeMiddleware())
    .use(serveStaticCode)
    .use(awaitElmMiddleware)
    .use(baseMiddleware(options.base))
    .use(serveCachedFiles)
    .use(vite.middlewares)
    .use(processRequest);

  httpServer.listen(port);
  /**
   * @param {http.IncomingMessage} request
   * @param {http.ServerResponse} response
   * @param {connect.NextHandleFunction} next
   */
  function processRequest(request, response, next) {
    if (request.url && request.url.startsWith("/stream")) {
      handleStream(request, response);
    } else if (request.url && request.url.startsWith("/_tests-preview")) {
      handleTestViewerPreview(request, response);
    } else if (request.url && request.url.startsWith("/_tests")) {
      handleTestViewer(request, response);
    } else {
      handleNavigationRequest(request, response, next);
    }
  }

  let testViewerDirty = true;
  let testViewerCompileError = null;

  /**
   * Serve the visual test viewer at /_tests.
   * Only recompiles when source files have changed (testViewerDirty flag).
   * Live reloads via the same SSE /stream mechanism as the main app.
   * Preserves viewer state (current test/step) across reloads via sessionStorage.
   */
  async function handleTestViewer(request, response) {
    try {
      if (testViewerDirty) {
        testViewerCompileError = null;
        try {
          await compileTestViewer();
        } catch (error) {
          testViewerCompileError = String(error);
        }
        testViewerDirty = false;
      }

      if (testViewerCompileError) {
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        response.end(testViewerErrorHtml(testViewerCompileError));
      } else {
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        response.end(testViewerHtml());
      }
    } catch (error) {
      response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      response.end(testViewerErrorHtml(String(error)));
    }
  }

  async function handleTestViewerPreview(request, response) {
    try {
      const userHeadTags = config.headTagsTemplate({ cliVersion: packageVersion });
      const previewHtml = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  ${userHeadTags}
</head>
<body>
  <div id="preview-root"></div>
</body>
</html>`;
      const processedHtml = await vite.transformIndexHtml(
        "/_tests-preview",
        previewHtml
      );
      response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      response.end(processedHtml);
    } catch (error) {
      response.writeHead(500, { "Content-Type": "text/plain" });
      response.end("Test viewer preview error: " + String(error));
    }
  }

  async function compileTestViewer() {
    const { discoverProgramTestModules } = await import("./commands/shared.js");
    const { writeFileIfChanged, ensureDirSync } = await import(
      "./file-helpers.js"
    );

    const allTests = (await discoverProgramTestModules()).map(
      ({ moduleName, values }) => ({ moduleName, values })
    );

    if (allTests.length === 0) {
      return;
    }

    // Generate TestViewer.elm
    const imports = allTests.map((t) => `import ${t.moduleName}`).join("\n");
    const namedSnapshotExprs = allTests
      .flatMap((t) =>
        t.values.map(
          (name) =>
            `Test.PagesProgram.toNamedSnapshots ${t.moduleName}.${name}`
        )
      )
      .join("\n            , ");

    const viewerElm = `module TestViewer exposing (main)

{-| Generated test viewer for dev server. -}

${imports}
import Test.PagesProgram
import Test.PagesProgram.Viewer as Viewer

main : Program Viewer.Flags Viewer.Model Viewer.Msg
main =
    Viewer.app
        (List.concat
            [ ${namedSnapshotExprs}
            ]
        )
`;

    const testViewerDir = path.join(
      process.cwd(),
      "elm-stuff/elm-pages/test-viewer"
    );
    ensureDirSync(testViewerDir);

    await writeFileIfChanged(
      path.join(testViewerDir, "TestViewer.elm"),
      viewerElm
    );

    // Compile in an isolated directory with its own elm.json so we don't
    // pollute the main app's source-directories or trigger Debug errors.

    // Create elm.json for the test viewer: same as the project but with
    // tests/ added to source-directories and paths adjusted to be relative.
    const elmJson = JSON.parse(
      fs.readFileSync(path.resolve("elm.json"), "utf8")
    );
    // Deep clone so we don't mutate shared nested objects.
    const testViewerElmJson = JSON.parse(JSON.stringify(elmJson));
    const extraSourceDirectories = ["tests"];
    if (fs.existsSync(path.resolve("snapshot-tests/src"))) {
      extraSourceDirectories.push("snapshot-tests/src");
    }
    testViewerElmJson["source-directories"] = elmJson["source-directories"]
      .filter((dir) => !dir.includes("elm-stuff/elm-pages/test-viewer"))
      .map((dir) => path.join("../../..", dir))
      .concat(extraSourceDirectories.map((dir) => path.join("../../..", dir)), ["."]);

    // Generated TestApp.elm imports Lamdera.Wire3 for codec support, and
    // Test.Html.Selector comes from elm-explorations/test. Neither is
    // automatically in the user's elm.json, so inject them here the same
    // way `elm-pages test` does.
    testViewerElmJson["dependencies"] = testViewerElmJson["dependencies"] || {};
    testViewerElmJson["dependencies"]["direct"] =
      testViewerElmJson["dependencies"]["direct"] || {};
    testViewerElmJson["dependencies"]["indirect"] =
      testViewerElmJson["dependencies"]["indirect"] || {};
    const ensureDirectDep = (pkg, version) => {
      testViewerElmJson["dependencies"]["direct"][pkg] = version;
      delete testViewerElmJson["dependencies"]["indirect"][pkg];
    };
    ensureDirectDep("lamdera/codecs", "1.0.0");
    ensureDirectDep("elm/bytes", "1.0.8");
    // Promote elm-explorations/test from test-dependencies if present,
    // then ensure a minimum version. `elm make` doesn't honor
    // test-dependencies, so tests referencing Test.Html.Selector must
    // see it as a regular dependency.
    const testDirect = (elmJson["test-dependencies"] || {}).direct || {};
    if (testDirect["elm-explorations/test"]) {
      ensureDirectDep(
        "elm-explorations/test",
        testDirect["elm-explorations/test"]
      );
    } else if (!testViewerElmJson["dependencies"]["direct"]["elm-explorations/test"]) {
      ensureDirectDep("elm-explorations/test", "2.2.1");
    }

    // `elm make` ignores test-dependencies, and leaving the cloned entries
    // in here makes Lamdera reject the elm.json when a test-dep was just
    // promoted into dependencies.direct (it sees the package listed twice).
    testViewerElmJson["test-dependencies"] = { direct: {}, indirect: {} };

    fs.writeFileSync(
      path.join(testViewerDir, "elm.json"),
      JSON.stringify(testViewerElmJson, null, 4)
    );

    try {
      const { spawnSync, execSync } = await import("node:child_process");
      // Use lamdera if available (needed for Wire3 codecs), fall back to elm
      let compiler = "elm";
      try {
        execSync("lamdera --help", { stdio: "ignore" });
        compiler = "lamdera";
      } catch (e) {
        // lamdera not available, use elm
      }
      const result = spawnSync(
        compiler,
        [
          "make",
          "TestViewer.elm",
          "--output=../../../.elm-pages/cache/test-viewer.js",
          "--debug",
        ],
        { stdio: "pipe", cwd: testViewerDir }
      );

      if (result.status !== 0) {
        const stderr = result.stderr ? result.stderr.toString() : "";
        console.error(
          kleur.yellow("Test viewer compilation failed (non-fatal):")
        );
        console.error(kleur.dim(stderr.slice(0, 500)));
        testViewerCompileError = stderr || "Compilation failed with no error output";
      } else {
        testViewerCompileError = null;
      }
    } catch (e) {
      console.error(kleur.yellow("Test viewer compilation error:"), e.message);
      testViewerCompileError = e.message;
    }
  }

  function testViewerHtml() {
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>elm-pages Test Viewer</title>
</head>
<body>
  <div id="app"></div>
  <script src="/test-viewer.js"></script>
  <script>
    var app = Elm.TestViewer.init({ node: document.getElementById("app") });

    // Live reload via SSE (same mechanism as elm-pages dev)
    var eventSource = new EventSource("/stream");
    eventSource.onmessage = function() {
      // Save viewer state before reload
      try {
        var model = document.querySelector('.viewer');
        if (model) {
          var stepCounter = document.querySelector('.step-counter');
          var stepMatch = stepCounter && stepCounter.textContent.match(/Step (\\d+)/);
          var testTabs = document.querySelectorAll('.test-tab-active, .test-list-row-selected');
          sessionStorage.setItem('elm-pages-test-viewer', JSON.stringify({
            timestamp: Date.now()
          }));
        }
      } catch(e) {}

      // Reload test-viewer.js by replacing the script tag
      var oldScript = document.querySelector('script[src^="/test-viewer.js"]');
      var newScript = document.createElement("script");
      newScript.src = "/test-viewer.js?t=" + Date.now();
      newScript.onload = function() { location.reload(); };
      if (oldScript && oldScript.parentNode) {
        oldScript.parentNode.replaceChild(newScript, oldScript);
      } else {
        document.body.appendChild(newScript);
      }
    };

    // Sync Elm's hidden .page-body into the preview iframe via polling.
    // innerHTML doesn't capture DOM properties (like input.value, checkbox.checked),
    // so we copy those separately after syncing HTML.
    var lastSynced = "";
    function syncProperties(source, target) {
      var sourceInputs = source.querySelectorAll('input, textarea, select');
      var targetInputs = target.querySelectorAll('input, textarea, select');
      for (var i = 0; i < sourceInputs.length && i < targetInputs.length; i++) {
        if (sourceInputs[i].value !== targetInputs[i].value) {
          targetInputs[i].value = sourceInputs[i].value;
        }
        if (sourceInputs[i].checked !== targetInputs[i].checked) {
          targetInputs[i].checked = sourceInputs[i].checked;
        }
      }
    }
    var lastHighlightJson = "";
    var lastScrolledHighlight = "";

    function findHighlightTarget(doc, selector) {
      if (!selector) return null;
      switch (selector.type) {
        case "id":
          return doc.getElementById(selector.id);
        case "tag":
          return doc.querySelector(selector.tag);
        case "tag-text": {
          var els = doc.querySelectorAll(selector.tag);
          for (var i = 0; i < els.length; i++) {
            if (els[i].textContent.trim().indexOf(selector.text) !== -1) return els[i];
          }
          return null;
        }
        case "form-field": {
          var form = doc.getElementById(selector.formId);
          if (form) {
            var input = form.querySelector('[name="' + selector.fieldName + '"]');
            if (input) return input;
          }
          return null;
        }
        case "label-text": {
          var labels = doc.querySelectorAll("label");
          for (var j = 0; j < labels.length; j++) {
            if (labels[j].textContent.indexOf(selector.text) !== -1) {
              var inp = labels[j].querySelector("input, textarea, select");
              if (inp) return inp;
            }
          }
          return null;
        }
        case "assertion":
        case "interaction-selectors": {
          // When scopes are present, narrow the search to the innermost scope element
          var searchRoot = doc;
          if (selector.scopes && selector.scopes.length > 0) {
            for (var si = 0; si < selector.scopes.length; si++) {
              var scopeEl = findAssertionTarget(searchRoot, selector.scopes[si]);
              if (scopeEl) searchRoot = scopeEl;
            }
          }
          return findAssertionTarget(searchRoot, selector.selectors);
        }
        default:
          return null;
      }
    }

    // Find the best element matching a list of assertion selectors.
    // Tries to find an element that satisfies all selectors combined.
    function findAssertionTarget(doc, selectors) {
      if (!selectors || selectors.length === 0) return null;

      // Build a list of candidate elements from the most specific selector,
      // then filter by the remaining ones.
      var candidates = null;
      for (var i = 0; i < selectors.length; i++) {
        var sel = selectors[i];
        var found = findByAssertionSelector(doc, sel);
        if (!found || found.length === 0) return null;
        if (candidates === null) {
          candidates = found;
        } else {
          // Intersect: keep only elements in both sets
          candidates = candidates.filter(function(el) { return found.indexOf(el) !== -1; });
        }
      }
      return candidates && candidates.length > 0 ? candidates[0] : null;
    }

    // Check if a single element matches a selector (without searching descendants).
    function elementMatchesSelector(el, sel) {
      switch (sel.kind) {
        case "id": return el.id === sel.value;
        case "class": return el.classList && el.classList.contains(sel.value);
        case "tag": return el.tagName && el.tagName.toLowerCase() === sel.value.toLowerCase();
        case "value": return ('value' in el) && el.value === sel.value;
        case "text": {
          for (var i = 0; i < el.childNodes.length; i++) {
            if (el.childNodes[i].nodeType === 3 && el.childNodes[i].textContent.indexOf(sel.value) !== -1) return true;
          }
          return false;
        }
        case "containing": {
          if (!sel.selectors) return false;
          for (var j = 0; j < sel.selectors.length; j++) {
            var inner = findByAssertionSelector(el, sel.selectors[j]);
            if (!inner || inner.length === 0) return false;
          }
          return true;
        }
        default: return false;
      }
    }

    // Find all elements matching a single assertion selector.
    // When doc is an Element (not Document), also checks the element itself.
    function findByAssertionSelector(doc, sel) {
      var results;
      switch (sel.kind) {
        case "id": {
          // Use querySelector instead of getElementById so it works on both Document and Element roots
          var el = doc.querySelector("#" + CSS.escape(sel.value));
          results = el ? [el] : [];
          break;
        }
        case "class":
          results = Array.from(doc.querySelectorAll("." + CSS.escape(sel.value)));
          break;
        case "tag":
          results = Array.from(doc.querySelectorAll(sel.value));
          break;
        case "value": {
          // Elm sets value as a DOM property, not an HTML attribute,
          // so querySelectorAll('[value=...]') won't find it. Check the property directly.
          var inputs = doc.querySelectorAll("input, textarea, select");
          var valResults = [];
          for (var vi = 0; vi < inputs.length; vi++) {
            if (inputs[vi].value === sel.value) valResults.push(inputs[vi]);
          }
          results = valResults;
          break;
        }
        case "text": {
          // Walk all elements to find those containing the text
          var all = doc.querySelectorAll("*");
          results = [];
          for (var i = 0; i < all.length; i++) {
            // Check direct text content (not just descendants)
            for (var j = 0; j < all[i].childNodes.length; j++) {
              if (all[i].childNodes[j].nodeType === 3 && all[i].childNodes[j].textContent.indexOf(sel.value) !== -1) {
                results.push(all[i]);
                break;
              }
            }
          }
          // If no direct text match, try any text content
          if (results.length === 0) {
            for (var k = 0; k < all.length; k++) {
              if (all[k].textContent.indexOf(sel.value) !== -1 && all[k].children.length === 0) {
                results.push(all[k]);
              }
            }
          }
          break;
        }
        case "containing": {
          // Find elements that contain descendants matching ALL inner selectors
          var all2 = doc.querySelectorAll("*");
          var results2 = [];
          for (var m = 0; m < all2.length; m++) {
            var parent = all2[m];
            var allMatch = true;
            for (var n = 0; n < sel.selectors.length; n++) {
              var inner = findByAssertionSelector(parent, sel.selectors[n]);
              if (!inner || inner.length === 0) { allMatch = false; break; }
            }
            if (allMatch) results2.push(parent);
          }
          results = results2;
          break;
        }
        default:
          return [];
      }
      // When searching within a scoped element, querySelectorAll only finds
      // descendants. Also check if the root element itself matches.
      if (doc.nodeType === 1 && elementMatchesSelector(doc, sel) && results.indexOf(doc) === -1) {
        results.unshift(doc);
      }
      return results;
    }

    // Pin a target element's :hover styles as inline declarations.
    // Walks the iframe's stylesheets, collects every rule whose selector
    // contains :hover and matches the element (with :hover stripped),
    // and copies those declarations onto el.style. The element's
    // existing inline-style cssText is saved in a data- attr so we
    // can restore it when the highlight clears.
    //
    // This is what Chrome DevTools' "Force element state" panel does;
    // there's no DOM API to flip :hover programmatically — the browser
    // only sets it from real mouse position.
    //
    // Skipped:
    //   - cross-origin stylesheets (.cssRules throws SecurityError)
    //   - pseudo-element hover rules like button:hover::before, since
    //     inline style can't represent pseudo-elements
    function pinHoverStyles(iframeDoc, el) {
      if (!el || el.dataset.elmPagesHoverPinned === "1") return;
      var sheets = iframeDoc.styleSheets;
      var pinnedAny = false;
      for (var s = 0; s < sheets.length; s++) {
        var rules;
        try { rules = sheets[s].cssRules; } catch (e) { continue; }
        if (!rules) continue;
        for (var r = 0; r < rules.length; r++) {
          var rule = rules[r];
          if (!rule.selectorText || !rule.style) continue;
          var selectors = rule.selectorText.split(",");
          for (var si = 0; si < selectors.length; si++) {
            var sel = selectors[si].trim();
            if (sel.indexOf(":hover") === -1) continue;
            if (sel.indexOf("::") !== -1) continue;
            var stripped = sel.replace(/:hover/g, "").trim();
            if (!stripped) continue;
            var matches = false;
            try { matches = el.matches(stripped); } catch (e) {}
            if (!matches) continue;
            if (!pinnedAny) {
              el.dataset.elmPagesHoverBackup = el.getAttribute("style") || "";
              pinnedAny = true;
            }
            var style = rule.style;
            for (var p = 0; p < style.length; p++) {
              var prop = style[p];
              el.style.setProperty(prop, style.getPropertyValue(prop), style.getPropertyPriority(prop));
            }
          }
        }
      }
      if (pinnedAny) el.dataset.elmPagesHoverPinned = "1";
    }

    function unpinHoverStyles(iframeDoc) {
      var pinned = iframeDoc.querySelectorAll('[data-elm-pages-hover-pinned="1"]');
      for (var i = 0; i < pinned.length; i++) {
        var el = pinned[i];
        var backup = el.dataset.elmPagesHoverBackup || "";
        if (backup) el.setAttribute("style", backup);
        else el.removeAttribute("style");
        delete el.dataset.elmPagesHoverPinned;
        delete el.dataset.elmPagesHoverBackup;
      }
    }

    function updateHighlight(iframeDoc, pageBody) {
      var highlightJson = pageBody ? pageBody.getAttribute("data-highlight") : null;

      // Remove old highlights (both target and scope) if selector changed
      if (highlightJson !== lastHighlightJson) {
        var old = iframeDoc.querySelectorAll(".__elm-pages-highlight, .__elm-pages-highlight-scope");
        for (var i = 0; i < old.length; i++) old[i].remove();
        unpinHoverStyles(iframeDoc);
        lastHighlightJson = highlightJson;
      }

      if (!highlightJson) return;

      var selector;
      try { selector = JSON.parse(highlightJson); } catch(e) { return; }

      var isAssertion = selector.type === "assertion";

      var el = findHighlightTarget(iframeDoc, selector);
      if (!el) {
        // Target not found, clean up any stale overlays
        var stale = iframeDoc.querySelectorAll(".__elm-pages-highlight, .__elm-pages-highlight-scope");
        for (var s = 0; s < stale.length; s++) stale[s].remove();
        unpinHoverStyles(iframeDoc);
        return;
      }

      // Pin :hover styles for interaction targets (clicks, form fills) so
      // the highlighted element shows the same visual state it would when
      // a real user is about to click it. Assertions skip this — they're
      // not "about to interact" with the element.
      if (!isAssertion) {
        pinHoverStyles(iframeDoc, el);
      }

      // Scroll element into view when highlight target changes
      if (highlightJson !== lastScrolledHighlight) {
        el.scrollIntoView({ block: "nearest", behavior: "smooth" });
        lastScrolledHighlight = highlightJson;
      }

      var scrollX = iframeDoc.defaultView.scrollX || 0;
      var scrollY = iframeDoc.defaultView.scrollY || 0;

      var rect = el.getBoundingClientRect();

      var overlay = iframeDoc.querySelector(".__elm-pages-highlight");
      if (!overlay) {
        overlay = iframeDoc.createElement("div");
        overlay.className = "__elm-pages-highlight";
        iframeDoc.body.appendChild(overlay);
      }

      // Green for assertions, purple for interactions
      if (isAssertion) {
        overlay.style.cssText = "position:absolute;pointer-events:none;z-index:2147483647;border:2px solid #7ee787;background:rgba(126,231,135,0.1);border-radius:3px;transition:all 0.15s ease;box-sizing:border-box;";
      } else {
        overlay.style.cssText = "position:absolute;pointer-events:none;z-index:2147483647;border:2px solid #a855f7;background:rgba(168,85,247,0.1);border-radius:3px;transition:all 0.15s ease;box-sizing:border-box;";
      }

      overlay.style.top = (rect.top + scrollY) + "px";
      overlay.style.left = (rect.left + scrollX) + "px";
      overlay.style.width = rect.width + "px";
      overlay.style.height = rect.height + "px";

      // Scope boundary overlays (dashed green border on container elements)
      // Remove stale scope overlays first
      var oldScopes = iframeDoc.querySelectorAll(".__elm-pages-highlight-scope");
      for (var ri = 0; ri < oldScopes.length; ri++) oldScopes[ri].remove();

      if (selector.scopes && selector.scopes.length > 0) {
        for (var si = 0; si < selector.scopes.length; si++) {
          var scopeEl = findAssertionTarget(iframeDoc, selector.scopes[si]);
          if (!scopeEl) continue;

          var scopeRect = scopeEl.getBoundingClientRect();
          var scopeOverlay = iframeDoc.createElement("div");
          scopeOverlay.className = "__elm-pages-highlight-scope";
          scopeOverlay.style.cssText = "position:absolute;pointer-events:none;z-index:2147483646;border:2px dashed rgba(126,231,135,0.4);background:rgba(126,231,135,0.03);border-radius:3px;transition:all 0.15s ease;box-sizing:border-box;";
          scopeOverlay.style.top = (scopeRect.top + scrollY) + "px";
          scopeOverlay.style.left = (scopeRect.left + scrollX) + "px";
          scopeOverlay.style.width = scopeRect.width + "px";
          scopeOverlay.style.height = scopeRect.height + "px";
          iframeDoc.body.appendChild(scopeOverlay);
        }
      }
    }

    // Prevent all interactive events in the preview iframe.
    // The preview is a static snapshot -- clicks, form submits, etc. would
    // navigate or blank the iframe since there's no Elm runtime.
    function disableIframeInteractions(iframeDoc) {
      if (iframeDoc.__interactionsDisabled) return;
      iframeDoc.addEventListener("click", function(e) { e.preventDefault(); e.stopPropagation(); }, true);
      iframeDoc.addEventListener("submit", function(e) { e.preventDefault(); e.stopPropagation(); }, true);
      iframeDoc.addEventListener("auxclick", function(e) { e.preventDefault(); e.stopPropagation(); }, true);
      iframeDoc.__interactionsDisabled = true;
    }

    setInterval(function() {
      var iframe = document.getElementById('preview-iframe');
      if (!iframe) return;
      try {
        var target = iframe.contentDocument && iframe.contentDocument.getElementById('preview-root');
        if (!target) return;
        disableIframeInteractions(iframe.contentDocument);
        var pageBody = document.querySelector('.page-body');
        var html = pageBody ? pageBody.innerHTML : "";
        if (html !== lastSynced) {
          target.innerHTML = html;
          lastSynced = html;
        }
        // Always sync properties (value can change without innerHTML changing)
        if (pageBody) syncProperties(pageBody, target);
        // Update element highlight overlay
        updateHighlight(iframe.contentDocument, pageBody);
      } catch(e) {
        // contentDocument may not be accessible yet
      }
    }, 50);
  </script>
</body>
</html>`;
  }

  function testViewerErrorHtml(errorMessage) {
    var escaped = errorMessage
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>elm-pages Test Viewer - Error</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #1a1a2e;
      color: #e0e0e0;
      height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 40px;
    }
    .error-container {
      max-width: 800px;
      width: 100%;
    }
    .error-header {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 20px;
    }
    .error-icon {
      width: 32px;
      height: 32px;
      border-radius: 50%;
      background: #e74c3c;
      color: #fff;
      font-size: 18px;
      font-weight: 700;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .error-title {
      color: #e74c3c;
      font-size: 20px;
      font-weight: 600;
    }
    .error-body {
      background: #0d1117;
      border: 1px solid #e74c3c;
      border-radius: 8px;
      padding: 20px;
      font-family: "SF Mono", "Fira Code", monospace;
      font-size: 13px;
      color: #e0a0a0;
      white-space: pre-wrap;
      word-break: break-word;
      max-height: 60vh;
      overflow: auto;
    }
    .hint {
      margin-top: 16px;
      color: #556677;
      font-size: 13px;
    }
  </style>
</head>
<body>
  <div class="error-container">
    <div class="error-header">
      <div class="error-icon">!</div>
      <div class="error-title">Test Viewer Compilation Failed</div>
    </div>
    <pre class="error-body">${escaped}</pre>
    <p class="hint">Fix the error and save -- the page will reload automatically.</p>
  </div>
  <script>
    var eventSource = new EventSource("/stream");
    eventSource.onmessage = function() { location.reload(); };
  </script>
</body>
</html>`;
  }

  watcher.on("all", async function (eventName, pathThatChanged) {
    if (pathThatChanged === "elm.json") {
      watchElmSourceDirs(false);
    } else if (
      pathThatChanged.startsWith("app/Route") &&
      !pathThatChanged.endsWith(".elm")
    ) {
      // this happens when a folder is created in app/Route. Ignore this case.
    } else if (pathThatChanged.endsWith(".elm")) {
      invalidatePool();
      if (elmMakeRunning) {
      } else {
        let codegenError = null;
        if (needToRerunCodegen(eventName, pathThatChanged)) {
          try {
            await codegen.generate(options.base);
          } catch (error) {
            codegenError = error;
          }
        }
        elmMakeRunning = true;
        if (codegenError) {
          const errorJson = JSON.stringify({
            type: "compile-errors",
            errors: [codegenError],
          });
          clientElmMakeProcess = Promise.reject(errorJson);
          pendingCliCompile = Promise.reject(errorJson);
        } else {
          clientElmMakeProcess = compileElmForBrowser(options, config);
          pendingCliCompile = compileCliApp(
            options,
            ".elm-pages/Main.elm",
            path.join(process.cwd(), "elm-stuff/elm-pages/", "elm.js"),
            "elm-stuff/elm-pages/",
            path.join("elm-stuff/elm-pages/", "elm.js")
          );
        }

        // Mark test viewer for recompilation regardless of main app result.
        // The test viewer compiles independently and may succeed even when
        // the main app fails (e.g., generated Main.elm is stale).
        testViewerDirty = true;
        Promise.all([clientElmMakeProcess, pendingCliCompile])
          .then(() => {
            elmMakeRunning = false;
          })
          .catch(() => {
            elmMakeRunning = false;
          });
        clients.forEach((client) => {
          client.response.write(`data: content.dat\n\n`);
        });
      }
    } else {
      // TODO use similar logic in the workers? Or don't use cache at all?
      // const changedPathRelative = path.relative(process.cwd(), pathThatChanged);
      //
      // Object.keys(global.staticHttpCache).forEach((backendTaskKey) => {
      //   if (backendTaskKey.includes(`file://${changedPathRelative}`)) {
      //     delete global.staticHttpCache[backendTaskKey];
      //   } else if (
      //     (eventName === "add" ||
      //       eventName === "unlink" ||
      //       eventName === "change" ||
      //       eventName === "addDir" ||
      //       eventName === "unlinkDir") &&
      //     backendTaskKey.startsWith("glob://")
      //   ) {
      //     delete global.staticHttpCache[backendTaskKey];
      //   }
      // });
      clients.forEach((client) => {
        client.response.write(`data: content.dat\n\n`);
      });
    }
  });

  /**
   * @param {http.IncomingMessage} request
   * @param {http.ServerResponse} response
   */
  function handleStream(request, response) {
    response.writeHead(200, {
      Connection: "keep-alive",
      "Content-Type": "text/event-stream",
    });
    const clientId = Date.now();
    clients.push({ id: clientId, response });
    request.on("close", () => {
      clients = clients.filter((client) => client.id !== clientId);
    });
  }

  /**
   * @param {string} pathThatChanged
   * @param {'add' | 'unlink' | 'addDir' | 'unlinkDir' | 'change'} eventName
   */
  function needToRerunCodegen(eventName, pathThatChanged) {
    return (
      (eventName === "add" || eventName === "unlink") &&
      pathThatChanged.match(/app\/Route\/.*\.elm/)
    );
  }

  /**
   * @param {string} pathname
   * @param {((value: any) => any) | null | undefined} onOk
   * @param {((reason: any) => PromiseLike<never>) | null | undefined} onErr
   * @param {{ method: string; hostname: string; query: string; headers: Object; host: string; pathname: string; port: string; protocol: string; rawUrl: string; }} serverRequest
   */
  function runRenderThread(serverRequest, pathname, onOk, onErr) {
    let cleanUpThread = () => {};
    return new Promise(async (resolve, reject) => {
      const readyThread = await waitForThread();
      cleanUpThread = () => {
        cleanUp(readyThread);
      };

      readyThread.ready = false;
      await pendingCliCompile;
      readyThread.used = true;
      readyThread.worker.postMessage({
        mode: "dev-server",
        pathname,
        serverRequest,
        portsFilePath: global.portsFilePath,
      });
      readyThread.worker.on("message", (message) => {
        if (message.tag === "done") {
          resolve(message.data);
        } else if (message.tag === "watch") {
          // console.log("@@@ WATCH", message.data);
          message.data.forEach((pattern) => watcher.add(pattern));
        } else if (message.tag === "error") {
          reject(message.data);
        } else {
          throw `Unhandled message: ${message}`;
        }
      });
      readyThread.worker.on("error", (error) => {
        reject(error.context);
      });
    })
      .then(onOk)
      .catch(onErr)
      .finally(() => {
        cleanUpThread();
      });
  }

  function cleanUp(thread) {
    thread.worker.removeAllListeners("message");
    thread.worker.removeAllListeners("error");
    thread.ready = true;
    runPendingWork();
  }

  /**
   * @param {http.IncomingMessage} req
   * @param {http.ServerResponse} res
   * @param {connect.NextHandleFunction} next
   */
  async function handleNavigationRequest(req, res, next) {
    const urlParts = new URL(req.url || "", `https://localhost:${port}`);
    const pathname = urlParts.pathname || "";
    try {
      await pendingCliCompile;
    } catch (error) {
      let isImplicitContractError = false;
      try {
        let jsonParsed = JSON.parse(error);
        isImplicitContractError =
          jsonParsed.errors &&
          jsonParsed.errors.some((errorItem) => errorItem.name === "Main");
      } catch (unexpectedError) {
        console.log("Unexpected error", unexpectedError);
      }
      if (isImplicitContractError) {
        const reviewOutput = await runElmReview();
        console.log(restoreColorSafe(reviewOutput));

        if (req.url.includes("content.dat")) {
          res.writeHead(500, { "Content-Type": "application/json" });
          if (emptyReviewError(reviewOutput)) {
            res.end(error);
          } else {
            res.end(reviewOutput);
          }
        } else {
          res.writeHead(500, { "Content-Type": "text/html" });
          res.end(errorHtml());
        }
      } else {
        console.log(restoreColorSafe(error));
        if (req.url.includes("content.dat")) {
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(error);
        } else {
          res.writeHead(500, { "Content-Type": "text/html" });
          res.end(errorHtml());
        }
      }
      return;
    }

    const requestTime = new Date();
    /** @type {string | null} */
    let body = null;

    req.on("data", function (data) {
      if (!body) {
        body = "";
      }
      body += data;
    });

    req.on("end", async function () {
      // TODO run render directly instead of in worker thread
      await runRenderThread(
        await reqToJson(req, body, requestTime),
        pathname,
        async function (renderResult) {
          const is404 = renderResult.is404;
          switch (renderResult.kind) {
            case "bytes": {
              // Create combined format for content.dat
              // Format: [4 bytes: frozen views JSON length][N bytes: JSON][remaining: ResponseSketch]
              // Extract frozen views from the HTML (needed for SPA navigation)
              const { regions: frozenViews, html: updatedHtml } = extractAndReplaceFrozenViews(renderResult.html || "");
              const frozenViewsJson = JSON.stringify(frozenViews);
              const frozenViewsBuffer = Buffer.from(frozenViewsJson, 'utf8');
              const lengthBuffer = Buffer.alloc(4);
              lengthBuffer.writeUInt32BE(frozenViewsBuffer.length, 0);
              const combinedBuffer = Buffer.concat([
                lengthBuffer,
                frozenViewsBuffer,
                toExactBuffer(renderResult.contentDatPayload)
              ]);
              res.writeHead(is404 ? 404 : renderResult.statusCode, {
                "Content-Type": "application/octet-stream",
                ...renderResult.headers,
              });
              res.end(combinedBuffer);
              break;
            }
            case "json": {
              // TODO is this used anymore? I Think it's a dead code path and can be deleted
              res.writeHead(is404 ? 404 : renderResult.statusCode, {
                "Content-Type": "application/json",
                ...renderResult.headers,
              });
              // is contentJson used any more? I think it can safely be deleted
              res.end(renderResult.contentJson);
              break;
            }
            case "html": {
              try {
                const template = templateHtml(true, config.headTagsTemplate);
                const processedTemplate = await vite.transformIndexHtml(
                  req.originalUrl,
                  template
                );
                const info = renderResult.htmlString;

                // Replace __STATIC__ placeholders in HTML with indices
                // (but don't include frozen views in bytesData - they're already in the rendered DOM)
                const updatedHtml = replaceFrozenViewPlaceholders(info.html || "");

                // Create combined format with empty frozen views for initial page load
                // (frozen views are already in the DOM, so client adopts from there)
                const emptyFrozenViews = {};
                const frozenViewsJson = JSON.stringify(emptyFrozenViews);
                const frozenViewsBuffer = Buffer.from(frozenViewsJson, 'utf8');
                const lengthBuffer = Buffer.alloc(4);
                lengthBuffer.writeUInt32BE(frozenViewsBuffer.length, 0);

                // Decode original bytesData and prepend empty frozen views header
                const originalBytes = Buffer.from(info.bytesData, 'base64');
                const combinedBuffer = Buffer.concat([
                  lengthBuffer,
                  frozenViewsBuffer,
                  originalBytes
                ]);
                const combinedBytesData = combinedBuffer.toString('base64');

                const renderedHtml = processedTemplate
                  .replace(
                    /<!--\s*PLACEHOLDER_HEAD_AND_DATA\s*-->/,
                    `${info.headTags}
                  <script id="__ELM_PAGES_BYTES_DATA__" type="application/octet-stream">${combinedBytesData}</script>`
                  )
                  .replace(/<!--\s*PLACEHOLDER_TITLE\s*-->/, info.title)
                  .replace(/<!--\s*PLACEHOLDER_HTML\s* -->/, updatedHtml)
                  .replace(
                    /<!-- ROOT -->\S*<html lang="en">/m,
                    info.rootElement
                  );
                setHeaders(res, renderResult.headers);
                res.writeHead(renderResult.statusCode, {
                  "Content-Type": "text/html",
                });
                res.end(renderedHtml);
              } catch (e) {
                vite.ssrFixStacktrace(e);
                next(e);
              }
              break;
            }
            case "api-response": {
              if (renderResult.body.kind === "server-response") {
                const serverResponse = renderResult.body;
                setHeaders(res, serverResponse.headers);
                res.writeHead(serverResponse.statusCode);
                res.end(serverResponse.body);
              } else if (renderResult.body.kind === "static-file") {
                let mimeType = mimeTypes.lookup(pathname) || "text/html";
                mimeType =
                  mimeType === "application/octet-stream"
                    ? "text/html"
                    : mimeType;
                res.writeHead(renderResult.statusCode, {
                  "Content-Type": mimeType,
                });
                res.end(renderResult.body.body);
                // TODO - if route is static, write file to api-route-cache/ directory
                // TODO - get 404 or other status code from elm-pages renderer
              } else {
                throw (
                  "Unexpected api-response renderResult: " +
                  JSON.stringify(renderResult, null, 2)
                );
              }
              break;
            }
            default: {
              console.dir(renderResult);
              throw "Unexpected renderResult kind: " + renderResult.kind;
            }
          }
        },

        function (error) {
          console.log(restoreColorSafe(error));
          if (req.url.includes("content.dat")) {
            res.writeHead(500, { "Content-Type": "application/json" });
            res.end(JSON.stringify(error));
          } else {
            res.writeHead(500, { "Content-Type": "text/html" });
            res.end(errorHtml());
          }
        }
      );
    });
  }

  /**
   * @param { http.ServerResponse } res
   * @param {{ [key: string]: string[]; }} headers
   */
  function setHeaders(res, headers) {
    Object.keys(headers).forEach(function (key) {
      res.setHeader(key, headers[key]);
    });
  }

  /**
   * @param {string} reviewReportJsonString
   */
  function emptyReviewError(reviewReportJsonString) {
    try {
      return JSON.parse(reviewReportJsonString).errors.length === 0;
    } catch (e) {
      console.trace("problem with format in reviewReportJsonString", e);
      return true;
    }
  }

  async function awaitElmMiddleware(req, res, next) {
    if (req.url && req.url.startsWith("/elm.js")) {
      try {
        await pendingCliCompile;
        await clientElmMakeProcess;
        next();
      } catch (elmCompilerError) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(elmCompilerError);
      }
    } else {
      next();
    }
  }

  /**
   * @returns {Promise<{ ready:boolean; worker: Worker }>}
   * */
  function waitForThread() {
    return new Promise((resolve, reject) => {
      const readyThread = pool.find((thread) => thread.ready);
      if (readyThread) {
        readyThread.ready = false;
        setImmediate(() => {
          resolve(readyThread);
        });
      } else {
        threadReadyQueue.push(resolve);
      }
    });
  }

  function runPendingWork() {
    restartIdleWorkersIfStale();
    const readyThreads = pool.filter((thread) => thread.ready);
    readyThreads.forEach((readyThread) => {
      const startTask = threadReadyQueue.shift();
      if (startTask) {
        // if we don't use setImmediate here, the remaining work will be done sequentially by a single worker
        // using setImmediate delegates a ready thread to each pending task until it runs out of ready workers
        // so the delegation is done sequentially, and the actual work is then executed
        setImmediate(() => {
          startTask(readyThread);
        });
      }
    });
  }

  /**
   * @param {string} basePath
   */
  function initWorker(basePath) {
    let newWorker = {
      worker: new Worker(path.join(__dirname, "./render-worker.js"), {
        env: SHARE_ENV,
        workerData: { basePath },
      }),
      ready: false,
      used: false,
    };
    newWorker.worker.once("online", () => {
      newWorker.ready = true;
    });
    return newWorker;
  }
}

function timeMiddleware() {
  return (req, res, next) => {
    const start = Date.now();
    const end = res.end;
    res.end = (...args) => {
      logTime(`${timeFrom(start)} ${prettifyUrl(req.url)}`);
      return end.call(res, ...args);
    };

    next();
  };
}

function prettifyUrl(url, root) {
  return kleur.dim(url);
}

/**
 * @param {string} string
 */
function logTime(string) {
  console.log("Ran in " + string);
}

/**
 * @param {number} start
 * @param {number} subtract
 */
function timeFrom(start, subtract = 0) {
  const time = Date.now() - start - subtract;
  const timeString = (time + `ms`).padEnd(5, " ");
  if (time < 10) {
    return kleur.green(timeString);
  } else if (time < 50) {
    return kleur.yellow(timeString);
  } else {
    return kleur.red(timeString);
  }
}

function errorHtml() {
  /*html*/
  return `<!DOCTYPE html>
  <html lang="en">
  <head>
    <link rel="stylesheet" href="/style.css">
    <link rel="stylesheet" href="/dev-style.css">
    <link rel="preload" href="/index.js" as="script">
    <!--<link rel="preload" href="/elm.js" as="script">-->
    <script src="/hmr.js" type="text/javascript"></script>
    <script src="/elm.js" type="text/javascript"></script>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <script>
    if ("serviceWorker" in navigator) {
      window.addEventListener("load", () => {
        navigator.serviceWorker.getRegistrations().then(function(registrations) {
          for (let registration of registrations) {
            registration.unregister()
          } 
        })
      });
    }

    connect(function() {}, true)
    </script>
    <title>Error</title>
    </head>
    <body></body>
  </html>
  `;
}

async function ensureRequiredExecutables() {
  const checks = await Promise.allSettled([
    which("lamdera"),
    which("elm-review"),
  ]);

  if (checks[0].status === "rejected") {
    throw "I couldn't find lamdera on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
  if (checks[1].status === "rejected") {
    throw "I couldn't find elm-review on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
}

/**
 * @param {http.IncomingMessage} req
 * @param {string | null} body
 * @param {Date} requestTime
 */
function reqToJson(req, body, requestTime) {
  return new Promise((resolve, reject) => {
    if (
      req.method === "POST" &&
      req.headers["content-type"] &&
      req.headers["content-type"].includes("multipart/form-data") &&
      body
    ) {
      try {
        const bb = busboy({
          headers: req.headers,
        });
        let fields = {};

        bb.on("file", (fieldname, file, info) => {
          const { filename, encoding, mimeType } = info;

          file.on("data", (data) => {
            fields[fieldname] = {
              filename,
              mimeType,
              body: data.toString(),
            };
          });
        });

        bb.on("field", (fieldName, value) => {
          fields[fieldName] = value;
        });

        // TODO skip parsing JSON and form data body if busboy doesn't run
        bb.on("close", () => {
          resolve(toJsonHelper(req, body, requestTime, fields));
        });
        bb.write(body);
      } catch (error) {
        resolve(toJsonHelper(req, body, requestTime, null));
      }
    } else {
      resolve(toJsonHelper(req, body, requestTime, null));
    }
  });
}

/**
 * @param {http.IncomingMessage} req
 * @param {string | null} body
 * @param {Date} requestTime
 * @param {Object | null} multiPartFormData
 * @returns {{method: string; rawUrl: string; body: string?; }}
 */
function toJsonHelper(req, body, requestTime, multiPartFormData) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  return {
    method: req.method,
    headers: req.headers || {},
    rawUrl: url.toString(),
    body: body,
    requestTime: Math.round(requestTime.getTime()),
    multiPartFormData: multiPartFormData,
  };
}
// TODO capture repeat entries into a list of values
// TODO have expect functions in Elm to handle expecting exactly one value, or getting first value only without failing if more
function paramsToObject(entries) {
  const result = {};
  for (const [key, value] of entries) {
    result[key] = value;
  }
  return result;
}
