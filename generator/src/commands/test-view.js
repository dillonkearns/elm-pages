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
import { restoreColorSafe } from "../error-formatter.js";
import { resolveTestInputPath } from "../resolve-elm-module.js";
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
    const outputPath = path.resolve("tests/viewer.html");
    const outputScriptPath = path.resolve("tests/viewer.js");
    const previewOutputPath = path.resolve("tests/viewer-preview.html");
    ensureDirSync(path.dirname(outputPath));

    console.log("Compiling test viewer...");

    const projDir = projectDirectory || ".";
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

    await writeFileIfChanged(
      outputPath,
      renderStaticViewerHtml({
        scriptSrc: path.basename(outputScriptPath),
        previewSrc: path.basename(previewOutputPath),
      })
    );
    await writeFileIfChanged(previewOutputPath, renderStaticViewerPreviewHtml());

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

export function renderStaticViewerHtml({ scriptSrc, previewSrc }) {
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
        default:
          return null;
      }
    }

    function updateHighlight(iframeDoc, pageBody) {
      var highlightJson = pageBody ? pageBody.getAttribute("data-highlight") : null;

      if (highlightJson !== lastHighlightJson) {
        var old = iframeDoc.querySelectorAll(".__elm-pages-highlight");
        for (var i = 0; i < old.length; i++) old[i].remove();
        lastHighlightJson = highlightJson;
      }

      if (!highlightJson) return;

      var selector;
      try { selector = JSON.parse(highlightJson); } catch (e) { return; }

      var el = findHighlightTarget(iframeDoc, selector);
      if (!el) {
        var stale = iframeDoc.querySelectorAll(".__elm-pages-highlight");
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
        overlay.style.cssText = "position:absolute;pointer-events:none;z-index:2147483647;border:2px solid #a855f7;background:rgba(168,85,247,0.1);border-radius:3px;transition:all 0.15s ease;box-sizing:border-box;";
        iframeDoc.body.appendChild(overlay);
      }

      overlay.style.top = (rect.top + scrollY) + "px";
      overlay.style.left = (rect.left + scrollX) + "px";
      overlay.style.width = rect.width + "px";
      overlay.style.height = rect.height + "px";
    }

    function ensurePreviewFrame() {
      var iframe = document.getElementById("preview-iframe");
      if (iframe && iframe.getAttribute("src") !== previewSrc) {
        iframe.setAttribute("src", previewSrc);
      }
      return iframe;
    }

    setInterval(function() {
      var iframe = ensurePreviewFrame();
      if (!iframe) return;

      try {
        var target = iframe.contentDocument && iframe.contentDocument.getElementById("preview-root");
        if (!target) return;

        var pageBody = document.querySelector(".page-body");
        var html = pageBody ? pageBody.innerHTML : "";
        if (html !== lastSynced) {
          target.innerHTML = html;
          lastSynced = html;
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

export function renderStaticViewerPreviewHtml() {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body>
  <div id="preview-root"></div>
</body>
</html>`;
}
