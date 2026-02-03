import * as fs from "./dir-helpers.js";
import * as fsPromises from "fs/promises";
import { runElmReview } from "./compile-elm.js";
import { patchFrozenViews } from "./frozen-view-codemod.js";
import { patchFrozenViewsESVD } from "./frozen-view-codemod-esvd.js";
import { restoreColorSafe } from "./error-formatter.js";
import * as path from "path";
import { spawn as spawnCallback } from "cross-spawn";
import * as codegen from "./codegen.js";
import * as terser from "terser";
import * as os from "os";
import { Worker, SHARE_ENV } from "worker_threads";
import { ensureDirSync } from "./file-helpers.js";
import { generateClientFolder, generateServerFolder, compareEphemeralFields, formatDisagreementError } from "./codegen.js";
import { default as which } from "which";
import { build } from "vite";
import * as preRenderHtml from "./pre-render-html.js";
import * as esbuild from "esbuild";
import { createHash } from "crypto";
import { merge_vite_configs } from "./vite-utils.js";
import { resolveConfig } from "./config.js";
import * as globby from "globby";
import { fileURLToPath } from "url";
import { copyFile } from "fs/promises";

let pool = [];
let pagesReady;
let pagesErrored;
let pages = new Promise((resolve, reject) => {
  pagesReady = resolve;
  pagesErrored = reject;
});
let pagesReadyCalled = false;
let activeWorkers = 0;
let buildError = false;

const OUTPUT_FILE_NAME = "elm.js";

process.on("unhandledRejection", (error) => {
  console.log(error);
  process.exitCode = 1;
});

function ELM_FILE_PATH() {
  return path.join(process.cwd(), "./elm-stuff/elm-pages", OUTPUT_FILE_NAME);
}

async function ensureRequiredDirs() {
  ensureDirSync(`dist`);
  ensureDirSync(path.join(process.cwd(), ".elm-pages", "http-response-cache"));
}

async function ensureRequiredExecutables() {
  try {
    await which("lamdera");
  } catch (error) {
    throw "I couldn't find lamdera on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
  try {
    await which("elm-optimize-level-2");
  } catch (error) {
    throw "I couldn't find elm-optimize-level-2 on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
  try {
    await which("elm-review");
  } catch (error) {
    throw "I couldn't find elm-review on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
}

export async function run(options) {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  console.warn = function (...messages) {
    // This is a temporary hack to avoid this warning. elm-pages manages compiling the Elm code without Vite's involvement, so it is external to Vite.
    // There is a pending issue to allow having external scripts in Vite, once this issue is fixed we can remove this hack:
    // https://github.com/vitejs/vite/issues/3533
    if (
      messages &&
      messages[0] &&
      !messages[0].startsWith(`<script src="/elm.js">`)
    ) {
      console.info(...messages);
    }
  };
  try {
    await ensureRequiredDirs();
    await ensureRequiredExecutables();
    // since init/update are never called in pre-renders, and BackendTask.Http is called using pure NodeJS HTTP fetching
    // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)

    const generateCode = codegen.generate(options.base);

    await generateCode;

    const config = await resolveConfig();
    await fsPromises.writeFile(
      "elm-stuff/elm-pages/index.html",
      preRenderHtml.templateHtml(false, config.headTagsTemplate)
    );
    const viteConfig = merge_vite_configs(
      {
        configFile: false,
        root: process.cwd(),
        base: options.base,
        assetsInclude: ["/elm-pages.js"],
        ssr: false,

        build: {
          manifest: "___vite-manifest___.json",
          outDir: "dist",
          rollupOptions: {
            input: "elm-stuff/elm-pages/index.html",
          },
        },
        optimizeDeps: {
          include: [],
        },
      },
      config.vite || {}
    );

    const buildComplete = build(viteConfig);
    const compileClientPromise = compileElm(options, config);
    await buildComplete;
    const clientResult = await compileClientPromise;
    const fullOutputPath = path.join(process.cwd(), `./dist/elm.js`);
    const withoutExtension = path.join(process.cwd(), `./dist/elm`);
    const browserElmHash = await fingerprintElmAsset(
      fullOutputPath,
      withoutExtension
    );
    const assetManifestPath = path.join(
      process.cwd(),
      "dist/___vite-manifest___.json"
    );
    const manifest = JSON.parse(
      await fsPromises.readFile(assetManifestPath, { encoding: "utf-8" })
    );
    const indexTemplate = await fsPromises.readFile(
      "dist/elm-stuff/elm-pages/index.html",
      "utf-8"
    );
    const preloadFiles = [
      `elm.${browserElmHash}.js`,
      ...Object.entries(manifest).map((entry) => entry[1].file),
    ].map((file) => path.join(options.base, file));
    const userProcessedPreloads = preloadFiles.flatMap((file) => {
      const userPreloadForFile = config.preloadTagForFile(file);
      if (userPreloadForFile === true) {
        return [defaultPreloadForFile(file)];
      } else if (userPreloadForFile === false) {
        return [];
      } else if (typeof userPreloadForFile === "string") {
        return [userPreloadForFile];
      } else {
        throw `I expected preloadTagForFile in elm-pages.config.mjs to return a string or boolean, but instead it returned: ${userPreloadForFile}`;
      }
    });

    const processedIndexTemplate = indexTemplate
      .replace("<!-- PLACEHOLDER_PRELOADS -->", userProcessedPreloads.join(""))
      .replace(
        '<script defer src="/elm.js" type="text/javascript"></script>',
        `<script defer src="/elm.${browserElmHash}.js" type="text/javascript"></script>`
      );
    await fsPromises.writeFile("dist/template.html", processedIndexTemplate);
    // await fsPromises.unlink(assetManifestPath);
    const portBackendTaskCompiled = esbuild
      .build({
        entryPoints: ["./custom-backend-task"],
        platform: "node",
        outfile: ".elm-pages/compiled-ports/custom-backend-task.mjs",
        assetNames: "[name]-[hash]",
        chunkNames: "chunks/[name]-[hash]",
        outExtension: { ".js": ".js" },
        metafile: true,
        bundle: true,
        format: "esm",
        packages: "external",
        logLevel: "silent",
      })
      .then((result) => {
        try {
          global.portsFilePath = Object.keys(result.metafile.outputs)[0];
        } catch (e) {}
      })
      .catch((error) => {
        const portBackendTaskFileFound =
          globby.globbySync("./custom-backend-task.*").length > 0;
        if (portBackendTaskFileFound) {
          // don't present error if there are no files matching custom-backend-task
          // if there are files matching custom-backend-task, warn the user in case something went wrong loading it
          console.error("Failed to start custom-backend-task watcher", error);
        }
      });

    global.XMLHttpRequest = {};
    const compileCliPromise = compileCliApp(options);
    try {
      const serverResult = await compileCliPromise;
      await portBackendTaskCompiled;

      // Validate ephemeral field agreement between server and client transforms
      if (serverResult.ephemeralFields && clientResult.ephemeralFields) {
        const disagreement = compareEphemeralFields(
          serverResult.ephemeralFields,
          clientResult.ephemeralFields
        );
        if (disagreement) {
          throw new Error(formatDisagreementError(disagreement));
        }
      }
      const inlineRenderCode = `
import * as renderer from "./render.js";
import * as elmModule from "${path.resolve("./elm-stuff/elm-pages/elm.cjs")}";
import * as url from 'url';
${
  global.portsFilePath
    ? `import * as customBackendTask from "${path.resolve(
        global.portsFilePath
      )}";`
    : `const customBackendTask = {};`
}

import * as preRenderHtml from "./pre-render-html.js";
import { extractAndReplaceFrozenViews } from "./extract-frozen-views.js";
const basePath = \`${options.base || "/"}\`;
const htmlTemplate = ${JSON.stringify(processedIndexTemplate)};
const mode = "build";
const addWatcher = () => {};

export async function render(request) {
  const requestTime = new Date();
  const response = await renderer.render(
    customBackendTask,
    basePath,
    elmModule.default,
    mode,
    (new url.URL(request.rawUrl)).pathname,
    request,
    addWatcher,
    false
  );
  if (response.kind === "bytes") {
    // Extract frozen views from HTML and prepend to content.dat
    const { regions: frozenViews } = extractAndReplaceFrozenViews(response.html || "");
    const frozenViewsJson = JSON.stringify(frozenViews);
    const frozenViewsBuffer = Buffer.from(frozenViewsJson, 'utf8');
    const lengthBuffer = Buffer.alloc(4);
    lengthBuffer.writeUInt32BE(frozenViewsBuffer.length, 0);
    const contentDatBuffer = Buffer.concat([
      lengthBuffer,
      frozenViewsBuffer,
      Buffer.from(response.contentDatPayload.buffer)
    ]);
    return {
        body: contentDatBuffer,
        statusCode: response.statusCode,
        kind: response.kind,
        headers: response.headers,
    }
  } else if (response.kind === "api-response") {
    // isBase64Encoded
    return {
        body: response.body.body,
        statusCode: response.body.statusCode,
        kind: response.kind,
        headers: response.body.headers,
        isBase64Encoded: response.body.isBase64Encoded,
    }
  } else {
    // Replace __STATIC__ placeholders with numeric IDs in the HTML
    const { html: updatedHtml } = extractAndReplaceFrozenViews(response.htmlString?.html || "");
    if (response.htmlString) {
      response.htmlString.html = updatedHtml;
    }

    // Add empty frozen views prefix to bytesData (decoder expects this format)
    if (response.contentDatPayload && response.htmlString) {
      const emptyFrozenViewsJson = JSON.stringify({});
      const emptyFrozenViewsBuffer = Buffer.from(emptyFrozenViewsJson, 'utf8');
      const emptyLengthBuffer = Buffer.alloc(4);
      emptyLengthBuffer.writeUInt32BE(emptyFrozenViewsBuffer.length, 0);
      const htmlBytesBuffer = Buffer.concat([
        emptyLengthBuffer,
        emptyFrozenViewsBuffer,
        Buffer.from(response.contentDatPayload.buffer)
      ]);
      response.htmlString.bytesData = htmlBytesBuffer.toString("base64");
    }

    return {
        body: preRenderHtml.replaceTemplate(htmlTemplate, response.htmlString),
        statusCode: response.statusCode,
        kind: response.kind,
        headers: response.headers,
    }
  }
}
`;
      await esbuild.build({
        format: "esm",
        platform: "node",
        stdin: { contents: inlineRenderCode, resolveDir: __dirname },
        bundle: true,
        // TODO do I need to make the outfile joined with the current working directory?

        outfile: ".elm-pages/compiled/render.mjs",
        // external: ["node:*", ...options.external],
        packages: "external",
        minify: true,
        // absWorkingDir: projectDirectory,
        // banner: { js: `#!/usr/bin/env node\n\n${ESM_REQUIRE_SHIM}` },
      });
    } catch (cliError) {
      // Check if this is an ephemeral field disagreement error - already formatted, just exit
      if (cliError.message && cliError.message.includes("EPHEMERAL FIELD DISAGREEMENT")) {
        console.error(cliError);
        throw cliError;  // Re-throw to outer catch
      }

      // TODO make sure not to print duplicate error output if cleaner review output is printed
      console.error(cliError);
      const reviewOutput = JSON.parse(await runElmReview());
      const isParsingError = reviewOutput.errors.some((reviewError) => {
        return reviewError.errors.some((item) => item.rule === "ParsingError");
      });
      if (isParsingError) {
        console.error(cliError);
      } else {
        console.error(restoreColorSafe(reviewOutput));
      }
      process.exit(1);
    }
    await portBackendTaskCompiled;
    const cliDone = runCli(options);
    await cliDone;

    await runAdapter(
      config.adapter ||
        function () {
          console.log(
            "No adapter configured in elm-pages.config.mjs. Skipping adapter step."
          );
        },
      processedIndexTemplate
    );
  } catch (error) {
    if (error) {
      console.error(restoreColorSafe(error));
    }
    buildError = true;
    process.exitCode = 1;
  }
}

/**
 * @param {string} basePath
 */
function initWorker(basePath, whenDone) {
  return new Promise((resolve, reject) => {
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);
    activeWorkers += 1;
    let newWorker = {
      worker: new Worker(path.join(__dirname, "./render-worker.js"), {
        env: SHARE_ENV,
        workerData: { basePath },
      }),
    };
    newWorker.worker.once("online", () => {
      newWorker.worker.on("message", (message) => {
        if (message.tag === "all-paths") {
          pagesReadyCalled = true;
          pagesReady(JSON.parse(message.data));
        } else if (message.tag === "error") {
          process.exitCode = 1;
          console.error(restoreColorSafe(message.data));
          if (!pagesReadyCalled) {
            // when there is a build error while resolving all-paths, we don't know which pages to build so we need to short-circuit
            // and give an error instead of trying to build the remaining pages to show as many errors as possible
            pagesReady([]);
            reject(message.data);
          }
          buildError = true;
          buildNextPage(newWorker, whenDone);
        } else if (message.tag === "done") {
          buildNextPage(newWorker, whenDone);
        } else {
          throw `Unhandled tag ${message.tag}`;
        }
      });
      newWorker.worker.on("error", (error) => {
        console.error("Unhandled worker exception", error);
        buildError = true;
        process.exitCode = 1;
        buildNextPage(newWorker, whenDone);
      });
      resolve(newWorker);
    });
  });
}

/**
 */
function prepareStaticPathsNew(thread) {
  thread.worker.postMessage({
    portsFilePath: global.portsFilePath,
    mode: "build",
    tag: "render",
    pathname: "/all-paths.json",
  });
}

async function buildNextPage(thread, allComplete) {
  let nextPage = (await pages).pop();
  if (nextPage) {
    thread.worker.postMessage({
      portsFilePath: global.portsFilePath,
      mode: "build",
      tag: "render",
      pathname: nextPage,
    });
  } else {
    thread.worker.terminate();
    activeWorkers -= 1;
    allComplete();
  }
}

function runCli(options) {
  return new Promise((resolve, reject) => {
    const whenDone = () => {
      if (activeWorkers === 0) {
        // wait for the remaining tasks in the pool to complete once the pages queue is emptied
        Promise.all(pool).then((value) => {
          if (buildError) {
            reject();
          } else {
            resolve(value);
          }
        });
      }
    };
    const cpuCount = os.cpus().length;

    const getPathsWorker = initWorker(options.base, whenDone);
    getPathsWorker.then(prepareStaticPathsNew);
    const threadsToCreate = Math.max(1, cpuCount - 1);
    pool.push(getPathsWorker);
    for (let index = 0; index < threadsToCreate - 1; index++) {
      pool.push(initWorker(options.base, whenDone));
    }
    pool.forEach((threadPromise) => {
      threadPromise.then((thread) => buildNextPage(thread, whenDone));
    });
  });
}

/**
 * Compile the client-side Elm code.
 * @returns {Promise<{ephemeralFields: Map<string, Set<string>>}>}
 */
async function compileElm(options, config) {
  ensureDirSync("dist");
  const fullOutputPath = path.join(process.cwd(), `./dist/elm.js`);
  const clientResult = await generateClientFolder(options.base);

  // NOTE: DCE transform is applied in generateClientFolder via runElmReviewCodemod.
  // It transforms the COPIED source in elm-stuff/elm-pages/client/app/, not the original.
  // This allows the CLI bundle (for extraction) to use original source while
  // the client bundle uses transformed source for dead-code elimination.

  await spawnElmMake(
    options.debug ? "debug" : "optimize",
    options,
    ".elm-pages/Main.elm",
    fullOutputPath,
    path.join(process.cwd(), "./elm-stuff/elm-pages/client")
  );

  // Apply frozen view adoption codemod to patch virtual-dom
  // Use elm-safe-virtual-dom specific patches if configured
  const elmCode = await fsPromises.readFile(fullOutputPath, "utf-8");
  const patchedCode = config.elmSafeVirtualDom
    ? patchFrozenViewsESVD(elmCode)
    : patchFrozenViews(elmCode);
  await fsPromises.writeFile(fullOutputPath, patchedCode);

  if (!options.debug) {
    await runTerser(fullOutputPath);
  }

  return { ephemeralFields: clientResult.ephemeralFields };
}

async function fingerprintElmAsset(fullOutputPath, withoutExtension) {
  const fileHash = await fsPromises
    .readFile(fullOutputPath, "utf8")
    .then(getAssetHash);
  await fsPromises.copyFile(
    fullOutputPath,
    `${withoutExtension}.${fileHash}.js`
  );
  return fileHash;
}

export function elmOptimizeLevel2(outputPath, cwd) {
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
      if (code === 0) {
        await copyFile(optimizedOutputPath, outputPath);
        resolve();
      } else {
        if (!buildError) {
          buildError = true;
          process.exitCode = 1;
          reject(
            `I encountered an error when running elm-optimize-level-2:\n\n ${commandOutput}`
          );
        } else {
          // avoid unhandled error printing duplicate message, let process.exit in top loop take over
        }
      }
    });
  });
}

/** @typedef {"debug" | "optimize" | "default"} CompileMode  */

/**
 * @param {CompileMode} mode
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string | undefined} cwd
 */
async function spawnElmMake(mode, options, elmEntrypointPath, outputPath, cwd) {
  await runElmMake(mode, options, elmEntrypointPath, outputPath, cwd);
  if (mode === "optimize") {
    await elmOptimizeLevel2(outputPath, cwd);
  }
  await fsPromises.writeFile(
    outputPath,
    (await fsPromises.readFile(outputPath, "utf-8")).replace(
      /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_FORM_TO_STRING.\)/g,
      "function appendSubmitter (myFormData, event) { event.submitter && event.submitter.name && event.submitter.name.length > 0 ? myFormData.append(event.submitter.name, event.submitter.value) : myFormData;  return myFormData }; return " +
        (options.debug
          ? "_Json_wrap(Array.from(appendSubmitter(new FormData(_Json_unwrap(event).target), _Json_unwrap(event))))"
          : "[...(appendSubmitter(new FormData(event.target), event))]")
    )
  );
}

function getAssetHash(content) {
  return createHash("sha256").update(content).digest("hex").slice(0, 8);
}

/**
 * @param {CompileMode} mode
 */
function modeToOptions(mode) {
  if (mode === "debug") {
    return ["--debug"];
  } else if (mode === "optimize") {
    return ["--optimize"];
  } else {
    return [];
  }
}

/**
 * @param {CompileMode} mode
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string | undefined} cwd
 */
function runElmMake(mode, options, elmEntrypointPath, outputPath, cwd) {
  return new Promise(async (resolve, reject) => {
    const executableName = options.executableName || "lamdera";
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
    if (await fs.fileExists(outputPath)) {
      await fsPromises.unlink(outputPath, {
        force: true /* ignore errors if file doesn't exist */,
      });
    }
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
        (await fs.fileExists(outputPath)) &&
        commandOutput === ""
      ) {
        resolve();
      } else {
        if (!buildError) {
          buildError = true;
          try {
            reject(restoreColorSafe(commandOutput));
          } catch (error) {
            reject(commandOutput);
          }
        } else {
          // avoid unhandled error printing duplicate message, let process.exit in top loop take over
        }
      }
    });
  });
}

/**
 * @param {string} filePath
 */
export async function runTerser(filePath) {
  console.log("Running terser");
  const minifiedElm = await terser.minify(
    (await fsPromises.readFile(filePath)).toString(),
    {
      ecma: 5,

      module: true,
      compress: {
        pure_funcs: [
          "F2",
          "F3",
          "F4",
          "F5",
          "F6",
          "F7",
          "F8",
          "F9",
          "A2",
          "A3",
          "A4",
          "A5",
          "A6",
          "A7",
          "A8",
          "A9",
        ],
        pure_getters: true,
        keep_fargs: false,
        unsafe_comps: true,
        unsafe: true,
        passes: 2,
      },
      mangle: {},
    }
  );
  if (minifiedElm.code) {
    await fsPromises.writeFile(filePath, minifiedElm.code);
  } else {
    throw "Error running terser.";
  }
}

/**
 * Compile the server-side CLI app.
 * @returns {Promise<{ephemeralFields: Map<string, Set<string>>}>}
 */
export async function compileCliApp(options) {
  // Generate server folder with server-specific codemods
  // This transforms Data -> Ephemeral, creates reduced Data, generates ephemeralToData
  // Skip for scripts (elm-pages run) that don't have routes/app folder
  let serverResult = { ephemeralFields: new Map() };
  if (!options.isScript) {
    serverResult = await generateServerFolder(options.base);
  }

  // Scripts use the original path (elm-stuff/elm-pages/.elm-pages/)
  // Full builds use the server path (elm-stuff/elm-pages/server/.elm-pages/)
  const elmPagesFolder = options.isScript
    ? "elm-stuff/elm-pages"
    : "elm-stuff/elm-pages/server";

  await spawnElmMake(
    // TODO should be --optimize, but there seems to be an issue with the html to JSON with --optimize
    options.debug ? "debug" : "optimize",
    options,
    path.join(
      process.cwd(),
      `${elmPagesFolder}/.elm-pages/${options.mainModule || "Main"}.elm`
    ),
    path.join(process.cwd(), "elm-stuff/elm-pages/elm.js"),
    path.join(process.cwd(), elmPagesFolder)
  );

  const elmFileContent = await fsPromises.readFile(ELM_FILE_PATH(), "utf-8");
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
if ( (typeof vNode !== "undefined" && vNode.$ === "#2") // normal/debug mode
     || (typeof vNode !== "undefined" && typeof vNode.$ === "undefined" && typeof vNode.a == "string" && typeof vNode.b == "object" ) // optimize mode
   ) {
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
    ELM_FILE_PATH().replace(/\.js$/, ".cjs"),
    applyScriptPatches(
      options,
      elmFileContent
        .replace(
          /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
          `return ${forceThunksSource}
  return _Json_wrap(forceThunks(html));
`
        )
        .replace(`console.log('App dying')`, "")
    )
  );

  return { ephemeralFields: serverResult.ephemeralFields };
}

function applyScriptPatches(options, input) {
  if (options.isScript) {
    return input.replace(
      `_Debug_crash(8, moduleName, region, message)`,
      "console.error('TODO in module `' + moduleName + '` ' + _Debug_regionToString(region) + '\\n\\n' + message); process.exitCode = 1; debugger; throw 'CRASH!';"
    );
  } else {
    return input;
  }
}

async function runAdapter(adaptFn, processedIndexTemplate) {
  try {
    await adaptFn({
      renderFunctionFilePath: "./.elm-pages/compiled/render.mjs",
      routePatterns: JSON.parse(
        await fsPromises.readFile("./dist/route-patterns.json", "utf-8")
      ),
      apiRoutePatterns: JSON.parse(
        await fsPromises.readFile("./dist/api-patterns.json", "utf-8")
      ),
    });
    console.log("Success - Adapter script complete");
  } catch (error) {
    console.trace("ERROR - Adapter script failed", error);
    try {
      console.error(JSON.stringify(error));
    } catch (parsingError) {
      console.error(error);
    }
    process.exit(1);
  }
}

// Source: https://github.com/vitejs/vite/blob/c53ffec3465d2d28d08d29ca61313469e03f5dd6/playground/ssr-vue/src/entry-server.js#L50-L68
/**
 * @param {string} file
 */
function defaultPreloadForFile(file) {
  if (/\/elm\.[a-f0-9]+\.js$/.test(file)) {
    return `<link rel="preload" as="script" href="${file}">`;
  } else if (file.endsWith(".js")) {
    return `<link rel="modulepreload" crossorigin href="${file}">`;
  } else if (file.endsWith(".css")) {
    return `<link rel="preload" href="${file}" as="style">`;
  } else if (file.endsWith(".woff")) {
    return ` <link rel="preload" href="${file}" as="font" type="font/woff" crossorigin>`;
  } else if (file.endsWith(".woff2")) {
    return ` <link rel="preload" href="${file}" as="font" type="font/woff2" crossorigin>`;
  } else if (file.endsWith(".gif")) {
    return ` <link rel="preload" href="${file}" as="image" type="image/gif">`;
  } else if (file.endsWith(".jpg") || file.endsWith(".jpeg")) {
    return ` <link rel="preload" href="${file}" as="image" type="image/jpeg">`;
  } else if (file.endsWith(".png")) {
    return ` <link rel="preload" href="${file}" as="image" type="image/png">`;
  } else {
    // TODO
    return "";
  }
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; body: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

/** @typedef {     { body: string; head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */

/**
 * @param {Arg} fromElm
 * @param {string} contentJsonString
 * @returns {string}
 */
