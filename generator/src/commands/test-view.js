/**
 * Test viewer command - compiles page tests into a browser-based visual stepper
 * and serves it locally so the preview can run through Vite HTML transforms.
 *
 * Discovers ProgramTest values in the given module, generates a viewer app
 * that wraps them with Test.PagesProgram.Viewer.app, serves the viewer and
 * preview routes over HTTP, and opens the local URL in the browser.
 *
 * Usage: elm-pages test-view tests/MyPageTests.elm
 *        elm-pages test-view  (auto-discovers test files)
 */

import * as path from "node:path";
import * as fs from "node:fs";
import * as http from "node:http";
import { default as connect } from "connect";
import { restoreColorSafe } from "../error-formatter.js";
import { resolveTestInputPath } from "../resolve-elm-module.js";
import { resolveConfig } from "../config.js";
import { packageVersion } from "../compatibility-key.js";
import { merge_vite_configs } from "../vite-utils.js";
import {
  printCaughtError,
  findProgramTestValues,
  discoverProgramTestModules,
} from "./shared.js";
import {
  ensureDirSync,
  writeFileIfChanged,
} from "../file-helpers.js";
import { generate } from "../codegen.js";

export const TEST_VIEWER_ROUTE = "/_tests";
export const TEST_VIEWER_PREVIEW_ROUTE = "/_tests-preview";
export const TEST_VIEWER_SCRIPT_ROUTE = "/test-viewer.js";

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

    let projectDirectory;
    let allTests = [];

    if (elmModulePath && elmModulePath !== "") {
      const resolved = await resolveTestInputPath(elmModulePath);
      projectDirectory = resolved.projectDirectory;
      const filePath = path.join(
        resolved.sourceDirectory,
        resolved.moduleName.replace(/\./g, "/") + ".elm"
      );
      const values = findProgramTestValues(filePath);
      if (values.length > 0) {
        allTests.push({ moduleName: resolved.moduleName, values });
      }
    } else {
      const candidates = discoverProgramTestModules();

      if (candidates.length === 0) {
        console.error(
          "No ProgramTest values found in tests/ or snapshot-tests/src/.\n\n" +
            "Create a test module that exposes values with a ProgramTest type annotation:\n\n" +
            "    myTest : ProgramTest Model Msg\n" +
            "    myTest =\n" +
            '        PagesProgram.start (TestApp.index {})\n' +
            '            |> PagesProgram.ensureViewHas [ text "Hello" ]\n'
        );
        process.exit(1);
      }

      projectDirectory = ".";
      allTests = candidates.map(({ moduleName, values }) => ({
        moduleName,
        values,
      }));
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
    // Write generated files to the isolated test-viewer build directory
    const projDir = projectDirectory || ".";
    const outputScriptPath = path.resolve(
      projDir,
      ".elm-pages/cache/test-viewer.js"
    );
    ensureDirSync(path.dirname(outputScriptPath));

    console.log("Compiling test viewer...");

    const config = await resolveConfig();
    const previewHeadTags = config.headTagsTemplate({
      cliVersion: packageVersion,
    });
    const testViewerBuildDir = path.resolve(
      projDir,
      "elm-stuff/elm-pages/test-viewer"
    );
    ensureDirSync(testViewerBuildDir);

    const viewerModule = generateViewerModule(allTests);
    await writeFileIfChanged(
      path.join(testViewerBuildDir, "TestViewer.elm"),
      viewerModule
    );

    const elmJsonPath = path.resolve(projDir, "elm.json");
    const elmJson = JSON.parse(fs.readFileSync(elmJsonPath, "utf8"));
    const testViewerElmJson = { ...elmJson };
    const extraSourceDirectories = ["tests"];
    if (fs.existsSync(path.resolve(projDir, "snapshot-tests/src"))) {
      extraSourceDirectories.push("snapshot-tests/src");
    }
    testViewerElmJson["source-directories"] = elmJson["source-directories"]
      .filter((dir) => !dir.includes("elm-stuff/elm-pages/test-viewer"))
      .map((dir) => path.join("../../..", dir))
      .concat(extraSourceDirectories.map((dir) => path.join("../../..", dir)), ["."]);
    fs.writeFileSync(
      path.join(testViewerBuildDir, "elm.json"),
      JSON.stringify(testViewerElmJson, null, 4)
    );

    const { spawnSync } = await import("node:child_process");

    // Use lamdera if available (needed for Wire3 codecs), fall back to elm
    const { execSync } = await import("node:child_process");
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
        `--output=${outputScriptPath}`,
        "--debug",
      ],
      {
        stdio: "inherit",
        cwd: testViewerBuildDir,
      }
    );

    if (result.status !== 0) {
      console.error("Failed to compile test viewer.");
      process.exit(1);
    }

    const { createServer: createViteServer } = await import("vite");
    const vite = await createViteServer(
      merge_vite_configs(
        {
          root: path.resolve(projDir),
          appType: "custom",
          server: {
            middlewareMode: true,
            hmr: false,
          },
        },
        config.vite || {}
      )
    );

    const viewerHtml = renderStaticViewerHtml({
      scriptSrc: TEST_VIEWER_SCRIPT_ROUTE,
      previewSrc: TEST_VIEWER_PREVIEW_ROUTE,
      previewBaseHref: "/",
    });
    const previewHtml = renderStaticViewerPreviewHtml({
      headTags: previewHeadTags,
      baseHref: "/",
    });

    const app = createTestViewerServerApp({
      viewerHtml,
      previewHtml,
      viewerScriptPath: outputScriptPath,
      vite,
    });

    const server = http.createServer(app);
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(0, "127.0.0.1", resolve);
    });

    const address = server.address();
    const viewerUrl = `http://127.0.0.1:${address.port}${TEST_VIEWER_ROUTE}`;

    const cleanup = async () => {
      process.off("SIGINT", handleSigint);
      process.off("SIGTERM", handleSigterm);
      await Promise.allSettled([
        vite.close(),
        new Promise((resolve) => server.close(() => resolve())),
      ]);
    };

    const handleSigint = async () => {
      await cleanup();
      process.exit(0);
    };

    const handleSigterm = async () => {
      await cleanup();
      process.exit(0);
    };

    process.on("SIGINT", handleSigint);
    process.on("SIGTERM", handleSigterm);

    console.log(`\nViewer available at: ${viewerUrl}`);
    console.log("Press Ctrl+C to stop the local test-view server.");

    // Open in browser
    const { exec } = await import("node:child_process");
    const openCmd =
      process.platform === "darwin"
        ? "open"
        : process.platform === "win32"
          ? "start"
          : "xdg-open";

    exec(`${openCmd} ${viewerUrl}`, (err) => {
      if (err) {
        console.log(`Open ${viewerUrl} in your browser to view tests.`);
      }
    });
  } catch (error) {
    printCaughtError(error, restoreColorSafe);
    process.exit(1);
  }
}

export function createTestViewerServerApp({
  viewerHtml,
  previewHtml,
  viewerScriptPath,
  vite,
}) {
  const app = connect();

  app.use((request, response, next) => {
    handleTestViewerRequest({
      request,
      response,
      next,
      viewerHtml,
      previewHtml,
      viewerScriptPath,
      vite,
    });
  });

  if (vite && vite.middlewares) {
    app.use(vite.middlewares);
  }

  return app;
}

function handleTestViewerRequest({
  request,
  response,
  next,
  viewerHtml,
  previewHtml,
  viewerScriptPath,
  vite,
}) {
  const requestUrl = request.url || "";

  if (requestUrl.startsWith(TEST_VIEWER_PREVIEW_ROUTE)) {
    Promise.resolve(
      vite.transformIndexHtml(TEST_VIEWER_PREVIEW_ROUTE, previewHtml)
    )
      .then((processedHtml) => {
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        response.end(processedHtml);
      })
      .catch((error) => {
        response.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
        response.end("Test viewer preview error: " + String(error));
      });
    return;
  }

  if (requestUrl.startsWith(TEST_VIEWER_ROUTE)) {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(viewerHtml);
    return;
  }

  if (requestUrl.startsWith(TEST_VIEWER_SCRIPT_ROUTE)) {
    fs.readFile(viewerScriptPath, (error, fileContents) => {
      if (error) {
        response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
        response.end("Viewer script not found.");
        return;
      }

      response.writeHead(200, {
        "Content-Type": "application/javascript; charset=utf-8",
      });
      response.end(fileContents);
    });
    return;
  }

  next();
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

function relativeBaseHref(fromDir, toDir) {
  const relativePath = path.relative(fromDir, toDir).split(path.sep).join("/");

  if (relativePath === "" || relativePath === ".") {
    return "./";
  }

  return relativePath.endsWith("/") ? relativePath : `${relativePath}/`;
}

function rewriteRootRelativeUrl(url, baseHref = "../") {
  if (!url || !url.startsWith("/") || url.startsWith("//")) {
    return url;
  }

  if (baseHref === "" || baseHref === "./") {
    return url.slice(1);
  }

  const normalizedBaseHref = baseHref.endsWith("/")
    ? baseHref
    : `${baseHref}/`;

  return `${normalizedBaseHref}${url.slice(1)}`;
}

function rewriteRootRelativeUrls(html, baseHref = "../") {
  if (!html) {
    return "";
  }

  return html
    .replace(/\b(href|src)="([^"]+)"/g, (_match, attr, url) => {
      return `${attr}="${rewriteRootRelativeUrl(url, baseHref)}"`;
    })
    .replace(/\b(href|src)='([^']+)'/g, (_match, attr, url) => {
      return `${attr}='${rewriteRootRelativeUrl(url, baseHref)}'`;
    });
}

export function renderStaticViewerHtml({
  scriptSrc,
  previewSrc,
  previewBaseHref = "../",
}) {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>elm-pages Test Viewer</title>
</head>
<body>
  <div id="app"></div>
  <script src="${scriptSrc}"></script>
  <script>
    Elm.TestViewer.init({ node: document.getElementById("app") });

    var previewSrc = ${JSON.stringify(previewSrc)};
    var previewBaseHref = ${JSON.stringify(previewBaseHref)};
    var lastSynced = "";
    var lastHighlightJson = "";
    var lastScrolledHighlight = "";

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

    function rewriteRootRelativeUrl(url, baseHref) {
      if (!url || url.charAt(0) !== "/" || url.slice(0, 2) === "//") {
        return url;
      }

      if (!baseHref || baseHref === "./") {
        return url.slice(1);
      }

      var normalizedBaseHref = baseHref.charAt(baseHref.length - 1) === "/"
        ? baseHref
        : baseHref + "/";

      return normalizedBaseHref + url.slice(1);
    }

    function rewriteRootRelativeUrls(html, baseHref) {
      if (!html) return "";

      return html
        .replace(/\\b(href|src)="([^"]+)"/g, function(_match, attr, url) {
          return attr + '="' + rewriteRootRelativeUrl(url, baseHref) + '"';
        })
        .replace(/\\b(href|src)='([^']+)'/g, function(_match, attr, url) {
          return attr + "='" + rewriteRootRelativeUrl(url, baseHref) + "'";
        });
    }

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

    function findAssertionTarget(doc, selectors) {
      if (!selectors || selectors.length === 0) return null;

      var candidates = null;
      for (var i = 0; i < selectors.length; i++) {
        var sel = selectors[i];
        var found = findByAssertionSelector(doc, sel);
        if (!found || found.length === 0) return null;
        if (candidates === null) {
          candidates = found;
        } else {
          candidates = candidates.filter(function(el) {
            return found.indexOf(el) !== -1;
          });
        }
      }
      return candidates && candidates.length > 0 ? candidates[0] : null;
    }

    function elementMatchesSelector(el, sel) {
      switch (sel.kind) {
        case "id":
          return el.id === sel.value;
        case "class":
          return el.classList && el.classList.contains(sel.value);
        case "tag":
          return el.tagName && el.tagName.toLowerCase() === sel.value.toLowerCase();
        case "value":
          return "value" in el && el.value === sel.value;
        case "text": {
          for (var i = 0; i < el.childNodes.length; i++) {
            if (
              el.childNodes[i].nodeType === 3 &&
              el.childNodes[i].textContent.indexOf(sel.value) !== -1
            ) {
              return true;
            }
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
        default:
          return false;
      }
    }

    function findByAssertionSelector(doc, sel) {
      var results;
      switch (sel.kind) {
        case "id": {
          var idEl = doc.querySelector("#" + CSS.escape(sel.value));
          results = idEl ? [idEl] : [];
          break;
        }
        case "class":
          results = Array.from(doc.querySelectorAll("." + CSS.escape(sel.value)));
          break;
        case "tag":
          results = Array.from(doc.querySelectorAll(sel.value));
          break;
        case "value": {
          var inputs = doc.querySelectorAll("input, textarea, select");
          var valueResults = [];
          for (var vi = 0; vi < inputs.length; vi++) {
            if (inputs[vi].value === sel.value) valueResults.push(inputs[vi]);
          }
          results = valueResults;
          break;
        }
        case "text": {
          var all = doc.querySelectorAll("*");
          results = [];
          for (var ti = 0; ti < all.length; ti++) {
            for (var tj = 0; tj < all[ti].childNodes.length; tj++) {
              if (
                all[ti].childNodes[tj].nodeType === 3 &&
                all[ti].childNodes[tj].textContent.indexOf(sel.value) !== -1
              ) {
                results.push(all[ti]);
                break;
              }
            }
          }
          if (results.length === 0) {
            for (var tk = 0; tk < all.length; tk++) {
              if (
                all[tk].textContent.indexOf(sel.value) !== -1 &&
                all[tk].children.length === 0
              ) {
                results.push(all[tk]);
              }
            }
          }
          break;
        }
        case "containing": {
          var allParents = doc.querySelectorAll("*");
          var containingResults = [];
          for (var ci = 0; ci < allParents.length; ci++) {
            var parent = allParents[ci];
            var allMatch = true;
            for (var cj = 0; cj < sel.selectors.length; cj++) {
              var innerMatches = findByAssertionSelector(parent, sel.selectors[cj]);
              if (!innerMatches || innerMatches.length === 0) {
                allMatch = false;
                break;
              }
            }
            if (allMatch) containingResults.push(parent);
          }
          results = containingResults;
          break;
        }
        default:
          return [];
      }

      if (
        doc.nodeType === 1 &&
        elementMatchesSelector(doc, sel) &&
        results.indexOf(doc) === -1
      ) {
        results.unshift(doc);
      }

      return results;
    }

    function updateHighlight(iframeDoc, pageBody) {
      var highlightJson = pageBody ? pageBody.getAttribute("data-highlight") : null;

      if (highlightJson !== lastHighlightJson) {
        var old = iframeDoc.querySelectorAll(".__elm-pages-highlight, .__elm-pages-highlight-scope");
        for (var i = 0; i < old.length; i++) old[i].remove();
        lastHighlightJson = highlightJson;
      }

      if (!highlightJson) return;

      var selector;
      try { selector = JSON.parse(highlightJson); } catch (e) { return; }

      var isAssertion = selector.type === "assertion";
      var el = findHighlightTarget(iframeDoc, selector);
      if (!el) {
        var stale = iframeDoc.querySelectorAll(".__elm-pages-highlight, .__elm-pages-highlight-scope");
        for (var s = 0; s < stale.length; s++) stale[s].remove();
        return;
      }

      if (highlightJson !== lastScrolledHighlight) {
        el.scrollIntoView({ block: "nearest", behavior: "smooth" });
        lastScrolledHighlight = highlightJson;
      }

      var rect = el.getBoundingClientRect();
      var scrollX = iframeDoc.defaultView.scrollX || 0;
      var scrollY = iframeDoc.defaultView.scrollY || 0;

      var overlay = iframeDoc.querySelector(".__elm-pages-highlight");
      if (!overlay) {
        overlay = iframeDoc.createElement("div");
        overlay.className = "__elm-pages-highlight";
        iframeDoc.body.appendChild(overlay);
      }

      if (isAssertion) {
        overlay.style.cssText = "position:absolute;pointer-events:none;z-index:2147483647;border:2px solid #7ee787;background:rgba(126,231,135,0.1);border-radius:3px;transition:all 0.15s ease;box-sizing:border-box;";
      } else {
        overlay.style.cssText = "position:absolute;pointer-events:none;z-index:2147483647;border:2px solid #a855f7;background:rgba(168,85,247,0.1);border-radius:3px;transition:all 0.15s ease;box-sizing:border-box;";
      }

      overlay.style.top = (rect.top + scrollY) + "px";
      overlay.style.left = (rect.left + scrollX) + "px";
      overlay.style.width = rect.width + "px";
      overlay.style.height = rect.height + "px";

      var oldScopes = iframeDoc.querySelectorAll(".__elm-pages-highlight-scope");
      for (var si = 0; si < oldScopes.length; si++) oldScopes[si].remove();

      if (selector.scopes && selector.scopes.length > 0) {
        for (var sj = 0; sj < selector.scopes.length; sj++) {
          var scopeEl = findAssertionTarget(iframeDoc, selector.scopes[sj]);
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

    function ensurePreviewFrame() {
      var iframe = document.getElementById("preview-iframe");
      if (iframe && iframe.getAttribute("src") !== previewSrc) {
        iframe.setAttribute("src", previewSrc);
      }
      return iframe;
    }

    function disableIframeInteractions(iframeDoc) {
      if (iframeDoc.__interactionsDisabled) return;
      iframeDoc.addEventListener("click", function(e) { e.preventDefault(); e.stopPropagation(); }, true);
      iframeDoc.addEventListener("submit", function(e) { e.preventDefault(); e.stopPropagation(); }, true);
      iframeDoc.addEventListener("auxclick", function(e) { e.preventDefault(); e.stopPropagation(); }, true);
      iframeDoc.__interactionsDisabled = true;
    }

    setInterval(function() {
      var iframe = ensurePreviewFrame();
      if (!iframe) return;

      try {
        var target = iframe.contentDocument && iframe.contentDocument.getElementById("preview-root");
        if (!target) return;
        disableIframeInteractions(iframe.contentDocument);

        var pageBody = document.querySelector(".page-body");
        var html = pageBody ? pageBody.innerHTML : "";
        var syncedHtml = rewriteRootRelativeUrls(html, previewBaseHref);
        if (syncedHtml !== lastSynced) {
          target.innerHTML = syncedHtml;
          lastSynced = syncedHtml;
        }

        if (pageBody) syncProperties(pageBody, target);
        updateHighlight(iframe.contentDocument, pageBody);
      } catch (e) {
        // iframe may not be ready yet
      }
    }, 50);
  </script>
</body>
</html>`;
}

export function renderStaticViewerPreviewHtml({
  headTags = "",
  baseHref = "../",
} = {}) {
  const previewHeadTags = rewriteRootRelativeUrls(headTags, baseHref);

  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  ${previewHeadTags}
</head>
<body>
  <div id="preview-root"></div>
</body>
</html>`;
}
