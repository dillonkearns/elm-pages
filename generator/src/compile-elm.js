import { spawn as spawnCallback } from "cross-spawn";
import * as fs from "fs";
import * as fsHelpers from "./dir-helpers.js";
import * as fsPromises from "fs/promises";
import * as path from "path";
import * as kleur from "kleur/colors";
import { inject } from "elm-hot";
import { fileURLToPath } from "url";
import { rewriteElmJson } from "./rewrite-elm-json-help.js";
import { ensureDirSync } from "./file-helpers.js";
import { patchStaticRegions } from "./static-region-codemod.js";
import { patchStaticRegionsESVD } from "./static-region-codemod-esvd.js";
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
  if (options.optimize) {
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

  // Apply transforms in sequence:
  // 1. elm-hot injection for development
  // 2. Form data stringify replacement
  // 3. Static region adoption patch
  let transformedCode = inject(rawElmCode);

  transformedCode = transformedCode.replace(
    /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_FORM_TO_STRING.\)/g,
    "let appendSubmitter = (myFormData, event) => { event.submitter && event.submitter.name && event.submitter.name.length > 0 ? myFormData.append(event.submitter.name, event.submitter.value) : myFormData;  return myFormData }; return " +
      (true
        ? // TODO remove hardcoding
          "_Json_wrap([...(appendSubmitter(new FormData(_Json_unwrap(event).target), _Json_unwrap(event)))])"
        : "[...(new FormData(event.target))")
  );

  // Apply static region adoption codemod
  // Use elm-safe-virtual-dom specific patches if configured
  transformedCode = config.elmSafeVirtualDom
    ? patchStaticRegionsESVD(transformedCode)
    : patchStaticRegions(transformedCode);

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
  // Source: https://github.com/elm-explorations/test/blob/d5eb84809de0f8bbf50303efd26889092c800609/src/Elm/Kernel/HtmlAsJson.js
  const forceThunksSource = ` _HtmlAsJson_toJson(x)
}

              var virtualDomKernelConstants =
  {
    nodeTypeTagger: 4,
    nodeTypeThunk: 5,
    kids: "e",
    refs: "l",
    thunk: "m",
    node: "k",
    value: "a"
  }

function forceThunks(vNode) {
  if (typeof vNode !== "undefined" && vNode.$ === "#2") {
    // This is a tuple (the kids : List (String, Html) field of a Keyed node); recurse into the right side of the tuple
    vNode.b = forceThunks(vNode.b);
  }
  if (typeof vNode !== 'undefined' && vNode.$ === virtualDomKernelConstants.nodeTypeThunk && !vNode[virtualDomKernelConstants.node]) {
    // This is a lazy node; evaluate it
    var args = vNode[virtualDomKernelConstants.thunk];
    vNode[virtualDomKernelConstants.node] = vNode[virtualDomKernelConstants.thunk].apply(args);
    // And then recurse into the evaluated node
    vNode[virtualDomKernelConstants.node] = forceThunks(vNode[virtualDomKernelConstants.node]);
  }
  if (typeof vNode !== 'undefined' && vNode.$ === virtualDomKernelConstants.nodeTypeTagger) {
    // This is an Html.map; recurse into the node it is wrapping
    vNode[virtualDomKernelConstants.node] = forceThunks(vNode[virtualDomKernelConstants.node]);
  }
  if (typeof vNode !== 'undefined' && typeof vNode[virtualDomKernelConstants.kids] !== 'undefined') {
    // This is something with children (either a node with kids : List Html, or keyed with kids : List (String, Html));
    // recurse into the children
    vNode[virtualDomKernelConstants.kids] = vNode[virtualDomKernelConstants.kids].map(forceThunks);
  }
  return vNode;
}

function _HtmlAsJson_toJson(html) {
`;

  await fsPromises.writeFile(
    readFrom.replace(/\.js$/, ".cjs"),
    elmFileContent
      .replace(
        /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
        "return " +
          // TODO should the logic for this be `if options.optimize`? Or does the first case not make sense at all?
          (true
            ? `${forceThunksSource}
  return _Json_wrap(forceThunks(html));
`
            : `${forceThunksSource}
return forceThunks(html);
`)
      )
      .replace(/console\.log..App dying../, "")
  );
}

/**
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string | undefined} cwd
 */
async function compileElm(options, elmEntrypointPath, outputPath, cwd) {
  await spawnElmMake(options, elmEntrypointPath, outputPath, cwd);
  if (!options.debug) {
    // TODO maybe pass in a boolean argument for whether it's build or dev server, and only do eol2 for build
    // await elmOptimizeLevel2(outputPath, cwd);
  }
}

function spawnElmMake(options, elmEntrypointPath, outputPath, cwd) {
  return new Promise(async (resolve, reject) => {
    try {
      await fsPromises.unlink(outputPath);
    } catch (e) {
      /* File may not exist, so ignore errors */
    }

    const subprocess = spawnCallback(
      `lamdera`,
      [
        "make",
        elmEntrypointPath,
        "--output",
        outputPath,
        // TODO use --optimize for prod build
        ...(options.debug ? ["--debug"] : []),
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
    subprocess.on("error", function () {
      reject(commandOutput);
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
  const startTime = Date.now();
  return new Promise((resolve, reject) => {
    const child = spawnCallback(
      `lamdera`,
      [
        "make",
        elmEntrypointPath,
        "--output",
        outputPath,
        ...(options.debug ? ["--debug"] : []),
        ...(options.optimize ? ["--optimize"] : []),
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
 * enabling dead-code elimination of static region dependencies.
 *
 * @param {string} [ cwd ]
 */
export async function runElmReviewForDCE(cwd) {
  const startTime = Date.now();
  console.log("Applying static region DCE transforms via elm-review...");

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

function elmOptimizeLevel2(outputPath, cwd) {
  return new Promise((resolve, reject) => {
    const optimizedOutputPath = outputPath + ".opt";
    const subprocess = spawnCallback(
      `elm-optimize-level-2`,
      [outputPath, "--output", optimizedOutputPath],
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

    subprocess.on("close", async (code) => {
      if (
        code === 0 &&
        commandOutput === "" &&
        (await fsHelpers.fileExists(optimizedOutputPath))
      ) {
        await fs.promises.copyFile(optimizedOutputPath, outputPath);
        resolve();
      } else {
        reject(commandOutput);
      }
    });
  });
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
