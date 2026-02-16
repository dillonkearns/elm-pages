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
import busboy from "busboy";
import { createServer as createViteServer } from "vite";
import * as esbuild from "esbuild";
import { merge_vite_configs } from "./vite-utils.js";
import { templateHtml } from "./pre-render-html.js";
import { resolveConfig } from "./config.js";
import {
  extractAndReplaceFrozenViews,
  replaceFrozenViewPlaceholders,
} from "./extract-frozen-views.js";
import { toExactBuffer } from "./binary-helpers.js";
import * as globby from "globby";
import { fileURLToPath } from "url";

/** @import {IncomingMessage} from "connect" */

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * @param {{ port: number; base: string; https: boolean; debug: boolean; }} options
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
  }

  const vite = await createViteServer(
    merge_vite_configs(
      {
        server: {
          middlewareMode: true,
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

  const app = connect()
    .use(timeMiddleware())
    .use(serveStaticCode)
    .use(awaitElmMiddleware)
    .use(baseMiddleware(options.base))
    .use(serveCachedFiles)
    .use(vite.middlewares)
    .use(processRequest);

  if (useHttps) {
    const ssl = await devcert.certificateFor("localhost");
    https.createServer(ssl, app).listen(port);
  } else {
    http.createServer(app).listen(port);
  }
  /**
   * @param {IncomingMessage} request
   * @param {http.ServerResponse} response
   * @param {import("connect").NextFunction} next
   */
  function processRequest(request, response, next) {
    if (request.url && request.url.startsWith("/stream")) {
      handleStream(request, response);
    } else {
      handleNavigationRequest(request, response, next);
    }
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
   * @param {IncomingMessage} request
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
   * @param {import("chokidar/handler.js").EventName} eventName
   */
  function needToRerunCodegen(eventName, pathThatChanged) {
    return (
      (eventName === "add" || eventName === "unlink") &&
      pathThatChanged.match(/app\/Route\/.*\.elm/)
    );
  }

  /**
   * @param {string} pathname
   * @param {((value: import("./render.js").RenderResult) => any) | null | undefined} onOk
   * @param {((reason: any) => void) | null | undefined} onErr
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
        reject(/** @type {any} */ (error).context);
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
   * @param {IncomingMessage} req
   * @param {http.ServerResponse} res
   * @param {import("connect").NextFunction} next
   */
  async function handleNavigationRequest(req, res, next) {
    const urlParts = new URL(req.url || "", `https://localhost:${port}`);
    const pathname = urlParts.pathname || "";
    try {
      await pendingCliCompile;
    } catch (error) {
      let isImplicitContractError = false;
      try {
        let jsonParsed = JSON.parse(/** @type {string} */ (error));
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
        console.log(restoreColorSafe(/** @type {string} */ (error)));
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
              const { regions: frozenViews, html: updatedHtml } =
                extractAndReplaceFrozenViews(renderResult.html || "");
              const frozenViewsJson = JSON.stringify(frozenViews);
              const frozenViewsBuffer = Buffer.from(frozenViewsJson, "utf8");
              const lengthBuffer = Buffer.alloc(4);
              lengthBuffer.writeUInt32BE(frozenViewsBuffer.length, 0);
              const combinedBuffer = Buffer.concat([
                lengthBuffer,
                frozenViewsBuffer,
                toExactBuffer(renderResult.contentDatPayload),
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
                const updatedHtml = replaceFrozenViewPlaceholders(
                  info.html || ""
                );

                // Create combined format with empty frozen views for initial page load
                // (frozen views are already in the DOM, so client adopts from there)
                const emptyFrozenViews = {};
                const frozenViewsJson = JSON.stringify(emptyFrozenViews);
                const frozenViewsBuffer = Buffer.from(frozenViewsJson, "utf8");
                const lengthBuffer = Buffer.alloc(4);
                lengthBuffer.writeUInt32BE(frozenViewsBuffer.length, 0);

                // Decode original bytesData and prepend empty frozen views header
                const originalBytes = Buffer.from(info.bytesData, "base64");
                const combinedBuffer = Buffer.concat([
                  lengthBuffer,
                  frozenViewsBuffer,
                  originalBytes,
                ]);
                const combinedBytesData = combinedBuffer.toString("base64");

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
                vite.ssrFixStacktrace(/** @type {Error} */ (e));
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
              throw (
                "Unexpected renderResult kind: " +
                /** @type {any} */ (renderResult).kind
              );
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
   * @returns {Promise<{ ready:boolean; worker: Worker; used: boolean; stale: boolean; }>}
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
 * @param {IncomingMessage} req
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
 * @param {IncomingMessage} req
 * @param {string | null} body
 * @param {Date} requestTime
 * @param {Object | null} multiPartFormData
 * @returns {{method: string; rawUrl: string; body: string?; headers: http.IncomingHttpHeaders; requestTime: number; multiPartFormData: Object | null}}
 */
function toJsonHelper(req, body, requestTime, multiPartFormData) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  return {
    method: req.method,
    headers: req.headers || {},
    rawUrl: url.toString(),
    body: body,
    requestTime: Math.round(requestTime.getTime()),
    multiPartFormData,
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
