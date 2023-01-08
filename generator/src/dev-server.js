const path = require("path");
const fs = require("fs");
const which = require("which");
const chokidar = require("chokidar");
const { URL } = require("url");
const {
  compileElmForBrowser,
  runElmReview,
  compileCliApp,
} = require("./compile-elm.js");
const http = require("http");
const https = require("https");
const codegen = require("./codegen.js");
const kleur = require("kleur");
const serveStatic = require("serve-static");
const connect = require("connect");
const { restoreColorSafe } = require("./error-formatter");
const { Worker, SHARE_ENV } = require("worker_threads");
const os = require("os");
const { ensureDirSync } = require("./file-helpers.js");
const baseMiddleware = require("./basepath-middleware.js");
const devcert = require("devcert");
const busboy = require("busboy");
const { createServer: createViteServer } = require("vite");
const cliVersion = require("../../package.json").version;
const esbuild = require("esbuild");
const { merge_vite_configs } = require("./vite-utils.js");
const { templateHtml } = require("./pre-render-html.js");
const { resolveConfig } = require("./config.js");
const globby = require("globby");

/**
 * @param {{ port: string; base: string; https: boolean; debug: boolean; }} options
 */
async function start(options) {
  let threadReadyQueue = [];
  let pool = [];
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

  await codegen.generate(options.base);
  try {
    await ensureRequiredExecutables();
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
  let clientElmMakeProcess = compileElmForBrowser(options);
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

  const config = await resolveConfig();
  const vite = await createViteServer(
    merge_vite_configs(
      {
        server: {
          middlewareMode: "ssr",
          base: options.base,
          port: options.port,
        },
        configFile: false,
        root: process.cwd(),
        base: options.base,
      },

      config.vite
    )
  );
  esbuild
    .build({
      entryPoints: ["./port-data-source"],
      platform: "node",
      assetNames: "[name]-[hash]",
      chunkNames: "chunks/[name]-[hash]",
      outExtension: { ".js": ".js" },
      metafile: true,
      bundle: true,
      watch: true,
      logLevel: "silent",

      outdir: ".elm-pages/compiled-ports",
      entryNames: "[dir]/[name]-[hash]",

      plugins: [
        {
          name: "example",
          setup(build) {
            build.onEnd((result) => {
              try {
                global.portsFilePath = Object.keys(result.metafile.outputs)[0];

                clients.forEach((client) => {
                  client.response.write(`data: content.dat\n\n`);
                });
              } catch (e) {}
            });
          },
        },
      ],
    })
    .then((result) => {
      console.log("Watching port-data-source...");
    })
    .catch((error) => {
      const portBackendTaskFileFound =
        globby.sync("./port-data-source.*").length > 0;
      if (portBackendTaskFileFound) {
        // don't present error if there are no files matching port-data-source
        // if there are files matching port-data-source, warn the user in case something went wrong loading it
        console.error("Failed to start port-data-source watcher", error);
      }
    });

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
   * @param {http.IncomingMessage} request
   * @param {http.ServerResponse} response
   * @param {connect.NextHandleFunction} next
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
    } else if (pathThatChanged.endsWith(".elm")) {
      if (elmMakeRunning) {
      } else {
        let codegenError = null;
        if (needToRerunCodegen(eventName, pathThatChanged)) {
          try {
            await codegen.generate(options.base);
            clientElmMakeProcess = compileElmForBrowser(options);
            pendingCliCompile = compileCliApp(
              options,
              ".elm-pages/Main.elm",
              path.join(process.cwd(), "elm-stuff/elm-pages/", "elm.js"),
              // "elm.js",
              "elm-stuff/elm-pages/",
              path.join("elm-stuff/elm-pages/", "elm.js")
            );

            Promise.all([clientElmMakeProcess, pendingCliCompile])
              .then(() => {
                elmMakeRunning = false;
              })
              .catch(() => {
                elmMakeRunning = false;
              });
            clients.forEach((client) => {
              client.response.write(`data: elm.js\n\n`);
            });
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
          clientElmMakeProcess = compileElmForBrowser(options);
          pendingCliCompile = compileCliApp(
            options,
            ".elm-pages/Main.elm",

            path.join(process.cwd(), "elm-stuff/elm-pages/", "elm.js"),

            // "elm.js",
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
              res.writeHead(is404 ? 404 : renderResult.statusCode, {
                "Content-Type": "application/octet-stream",
                ...renderResult.headers,
              });
              res.end(Buffer.from(renderResult.contentDatPayload.buffer));
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
                const renderedHtml = processedTemplate
                  .replace(
                    /<!--\s*PLACEHOLDER_HEAD_AND_DATA\s*-->/,
                    `${info.headTags}
                  <script id="__ELM_PAGES_BYTES_DATA__" type="application/octet-stream">${info.bytesData}</script>`
                  )
                  .replace(/<!--\s*PLACEHOLDER_TITLE\s*-->/, info.title)
                  .replace(/<!--\s*PLACEHOLDER_HTML\s* -->/, info.html)
                  .replace(
                    /<!-- ROOT -->\S*<html lang="en">/m,
                    info.rootElement
                  );
                res.writeHead(renderResult.statusCode, {
                  "Content-Type": "text/html",
                  ...renderResult.headers,
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
                res.writeHead(
                  serverResponse.statusCode,
                  serverResponse.headers
                );
                res.end(serverResponse.body);
              } else if (renderResult.body.kind === "static-file") {
                let mimeType = serveStatic.mime.lookup(pathname || "text/html");
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
  try {
    await which("lamdera");
  } catch (error) {
    throw "I couldn't find lamdera on the PATH. Please ensure it's installed, either globally, or locally. If it's installed locally, ensure you're running through an NPM script or with npx so the PATH is configured to include it.";
  }
  try {
    await which("elm-review");
  } catch (error) {
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
module.exports = { start };
