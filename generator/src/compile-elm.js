import { spawn as spawnCallback } from "cross-spawn";
import * as fs from "fs";
import * as fsHelpers from "./dir-helpers.js";
import * as fsPromises from "fs/promises";
import * as path from "path";
import * as kleur from "kleur/colors";
import { fileURLToPath } from "url";
import { rewriteElmJson } from "./rewrite-elm-json-help.js";
import { patchFrozenViews } from "./frozen-view-codemod.js";
import { requireLamdera } from "./commands/shared.js";
import { patchCompiledCliApp } from "./patch-compiled-cli-app.js";
import { withTypeFingerprint } from "./type-fingerprint.js";
import { transform as eol2Transform } from "elm-optimize-level-2";
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export async function compileElmForBrowser(options, config = {}) {
  // TODO do I need to make sure this is run from the right cwd? Before it was run outside of this function in the global scope, need to make sure that doesn't change semantics.
  const pathToClientElm = path.join(
    process.cwd(),
    "elm-stuff/elm-pages/",
    "browser-elm.js"
  );
  const secretDir = path.join(process.cwd(), "elm-stuff/elm-pages/browser-elm");
  await fsHelpers.tryMkdir(secretDir);

  // For production builds, apply DCE transform via elm-review
  if (options.optimize === "2" || options.optimize === true) {
    await runElmReviewForDCE();
  }

  rewriteElmJson(process.cwd(), secretDir, function (elmJson) {
    elmJson["source-directories"] = elmJson["source-directories"].map(
      (item) => {
        return "../../../" + item;
      }
    );
    return elmJson;
  });
  await runElm(
    options,
    "../../../.elm-pages/Main.elm",
    pathToClientElm,
    secretDir
  );
  const rawElmCode = await fs.promises.readFile(pathToClientElm, "utf-8");

  // Hot reloading needs no transform here: Lamdera builds it into the compiled
  // code (`Elm.hot.reload`), and `static-code/hmr.js` calls it in the browser.
  //
  // Apply transforms in sequence:
  // 1. Form data stringify replacement
  // 2. Frozen view adoption patch
  // 3. Record the fingerprint of the app's types, which `hmr.js` uses to
  //    decide between hot reloading and loading the page again
  let transformedCode = rawElmCode;

  transformedCode = transformedCode.replace(
    /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_FORM_TO_STRING.\)/g,
    "let appendSubmitter = (myFormData, event) => { event.submitter && event.submitter.name && event.submitter.name.length > 0 ? myFormData.append(event.submitter.name, event.submitter.value) : myFormData;  return myFormData }; return " +
      (true
        ? // TODO remove hardcoding
          "_Json_wrap([...(appendSubmitter(new FormData(_Json_unwrap(event).target), _Json_unwrap(event)))])"
        : "[...(new FormData(event.target))")
  );

  // Patch the virtual DOM so it can draw frozen views
  transformedCode = patchFrozenViews(transformedCode);

  transformedCode = withTypeFingerprint(transformedCode);

  return fs.promises.writeFile("./.elm-pages/cache/elm.js", transformedCode);
}

export async function compileCliApp(
  options,
  elmEntrypointPath,
  outputPath,
  cwd,
  readFrom
) {
  await compileElm(options, elmEntrypointPath, outputPath, cwd);

  const elmFileContent = await fsPromises.readFile(readFrom, "utf-8");
  await fsPromises.writeFile(
    readFrom.replace(/\.js$/, ".cjs"),
    patchCompiledCliApp(elmFileContent)
  );
}

/**
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string | undefined} cwd
 */
async function compileElm(options, elmEntrypointPath, outputPath, cwd) {
  await spawnElmMake(options, elmEntrypointPath, outputPath, cwd);
  if (options.optimize === "2" || options.optimize === true) {
    await elmOptimizeLevel2(outputPath, cwd);
  }
}

async function spawnElmMake(options, elmEntrypointPath, outputPath, cwd) {
  const executableName = await requireLamdera();
  const mode = resolveCompileMode(options);
  try {
    await fsPromises.unlink(outputPath);
  } catch (e) {
    /* File may not exist, so ignore errors */
  }

  return new Promise((resolve, reject) => {
    const subprocess = spawnCallback(
      executableName,
      [
        "make",
        elmEntrypointPath,
        "--output",
        outputPath,
        ...modeToOptions(mode),
        "--report",
        "json",
      ],
      {
        // ignore stdout
        // stdio: ["inherit", "ignore", "inherit"],

        cwd: cwd,
      }
    );
    let commandOutput = "";

    subprocess.stderr.on("data", function (data) {
      commandOutput += data;
    });
    subprocess.on("error", function (err) {
      reject(commandOutput || err.message);
    });

    subprocess.on("close", async (code) => {
      if (
        code == 0 &&
        (await fsHelpers.fileExists(outputPath)) &&
        commandOutput === ""
      ) {
        resolve();
      } else {
        reject(commandOutput);
      }
    });
  });
}

/**
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string} [cwd]
 * @param {{ debug: boolean; }} options
 */
async function runElm(options, elmEntrypointPath, outputPath, cwd) {
  const executableName = await requireLamdera();
  const mode = resolveCompileMode(options);
  const startTime = Date.now();
  return new Promise((resolve, reject) => {
    const child = spawnCallback(
      executableName,
      [
        "make",
        elmEntrypointPath,
        "--output",
        outputPath,
        ...modeToOptions(mode),
        "--report",
        "json",
      ],
      { cwd: cwd }
    );

    let scriptOutput = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.on("error", function (err) {
      reject(scriptOutput || err.message);
    });

    child.on("close", function (code) {
      if (code === 0) {
        console.log(
          `Ran elm make ${elmEntrypointPath} in ${timeFrom(startTime)}`
        );
        resolve();
      } else {
        reject(scriptOutput);
      }
    });
  });
}

/**
 * @param {string} [ cwd ]
 */
export async function runElmReview(cwd) {
  const startTime = Date.now();
  return new Promise((resolve, reject) => {
    const child = spawnCallback(
      `elm-review`,
      [
        "--report",
        "json",
        "--namespace",
        "elm-pages",
        "--config",
        path.join(__dirname, "../../generator/review"),
      ],
      { cwd: cwd }
    );

    let scriptOutput = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.on("close", function (code) {
      console.log(`Ran elm-review in ${timeFrom(startTime)}`);
      if (code === 0) {
        resolve(scriptOutput);
      } else {
        resolve(scriptOutput);
      }
    });
  });
}

/**
 * Run elm-review with the dead-code-review config to apply DCE transforms.
 * This transforms View.renderStatic calls to View.embedStatic (View.Static.adopt ...)
 * enabling dead-code elimination of frozen view dependencies.
 *
 * @param {string} [ cwd ]
 */
export async function runElmReviewForDCE(cwd) {
  const startTime = Date.now();
  console.log("Applying frozen view DCE transforms via elm-review...");

  return new Promise((resolve, reject) => {
    const child = spawnCallback(
      `elm-review`,
      [
        "--fix-all-without-prompt",
        "--namespace",
        "elm-pages-dce",
        "--config",
        path.join(__dirname, "../../generator/dead-code-review"),
      ],
      { cwd: cwd }
    );

    let scriptOutput = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.on("close", function (code) {
      console.log(`Ran elm-review DCE transform in ${timeFrom(startTime)}`);
      if (code === 0) {
        console.log("DCE transforms applied successfully");
        resolve(scriptOutput);
      } else {
        // elm-review returns non-zero if it made fixes, which is expected
        // We only reject on actual errors
        if (scriptOutput.includes("error")) {
          reject(scriptOutput);
        } else {
          console.log("DCE transforms applied (with fixes)");
          resolve(scriptOutput);
        }
      }
    });
  });
}

/** @typedef {"debug" | "optimize" | "default"} CompileMode */

/** Derive compile mode from options */
export function resolveCompileMode(options) {
  if (options.debug) return "debug";
  if (options.optimize === false || options.optimize === "0") return "default";
  return "optimize"; // covers true, "1", "2", undefined
}

/**
 * @param {CompileMode} mode
 */
export function modeToOptions(mode) {
  if (mode === "debug") {
    return ["--debug"];
  } else if (mode === "optimize") {
    return ["--optimize"];
  } else {
    return [];
  }
}

export async function elmOptimizeLevel2(outputPath, cwd, { o3 = false } = {}) {
  const fullPath = cwd ? path.resolve(cwd, outputPath) : outputPath;
  const jsSource = await fsPromises.readFile(fullPath, "utf-8");
  const optimized = await eol2Transform(jsSource, o3);
  await fsPromises.writeFile(fullPath, optimized);
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
