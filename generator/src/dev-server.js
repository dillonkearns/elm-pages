const path = require("path");
const fs = require("fs");
const chokidar = require("chokidar");
const { spawnElmMake, compileElmForBrowser } = require("./compile-elm.js");
const http = require("http");
const codegen = require("./codegen.js");
const kleur = require("kleur");
const serveStatic = require("serve-static");
const connect = require("connect");
const { restoreColor } = require("./error-formatter");
const { Worker, SHARE_ENV } = require("worker_threads");
const os = require("os");
const { ensureDirSync } = require("./file-helpers.js");
const baseMiddleware = require("./basepath-middleware.js");

/**
 * @param {{ port: string; base: string }} options
 */
async function start(options) {
  let threadReadyQueue = [];
  let pool = [];
  ensureDirSync(path.join(process.cwd(), ".elm-pages", "http-response-cache"));
  const cpuCount = os.cpus().length;

  const port = options.port;
  let elmMakeRunning = true;

  const serve = serveStatic("public/", { index: false });
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
  let clientElmMakeProcess = compileElmForBrowser();
  let pendingCliCompile = compileCliApp();
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
        `<http://localhost:${port}>`
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
    watcher.add("./public/*.css");
    watcher.add("./port-data-source.js");
  }

  async function compileCliApp() {
    await spawnElmMake(
      ".elm-pages/TemplateModulesBeta.elm",
      "elm.js",
      "elm-stuff/elm-pages/"
    );
  }

  const app = connect()
    .use(timeMiddleware())
    .use(baseMiddleware(options.base))
    .use(awaitElmMiddleware)
    .use(serveCachedFiles)
    .use(serveStaticCode)
    .use(serve)
    .use(processRequest);
  http.createServer(app).listen(port);
  /**
   * @param {http.IncomingMessage} request
   * @param {http.ServerResponse} response
   * @param {connect.NextHandleFunction} next
   */
  async function processRequest(request, response, next) {
    if (request.url && request.url.startsWith("/stream")) {
      handleStream(request, response);
    } else {
      await handleNavigationRequest(request, response, next);
    }
  }

  watcher.on("all", async function (eventName, pathThatChanged) {
    // console.log({ pathThatChanged });
    if (pathThatChanged === "elm.json") {
      watchElmSourceDirs(false);
    } else if (pathThatChanged.endsWith(".css")) {
      clients.forEach((client) => {
        client.response.write(`data: style.css\n\n`);
      });
    } else if (pathThatChanged.endsWith(".elm")) {
      if (elmMakeRunning) {
      } else {
        let codegenError = null;
        if (needToRerunCodegen(eventName, pathThatChanged)) {
          try {
            await codegen.generate(options.base);
            clientElmMakeProcess = compileElmForBrowser();
            pendingCliCompile = compileCliApp();

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
          clientElmMakeProcess = compileElmForBrowser();
          pendingCliCompile = compileCliApp();
        }

        Promise.all([clientElmMakeProcess, pendingCliCompile])
          .then(() => {
            elmMakeRunning = false;
          })
          .catch(() => {
            elmMakeRunning = false;
          });
        clients.forEach((client) => {
          client.response.write(`data: content.json\n\n`);
        });
      }
    } else {
      // TODO use similar logic in the workers? Or don't use cache at all?
      // const changedPathRelative = path.relative(process.cwd(), pathThatChanged);
      //
      // Object.keys(global.staticHttpCache).forEach((dataSourceKey) => {
      //   if (dataSourceKey.includes(`file://${changedPathRelative}`)) {
      //     delete global.staticHttpCache[dataSourceKey];
      //   } else if (
      //     (eventName === "add" ||
      //       eventName === "unlink" ||
      //       eventName === "change" ||
      //       eventName === "addDir" ||
      //       eventName === "unlinkDir") &&
      //     dataSourceKey.startsWith("glob://")
      //   ) {
      //     delete global.staticHttpCache[dataSourceKey];
      //   }
      // });
      clients.forEach((client) => {
        client.response.write(`data: content.json\n\n`);
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
      pathThatChanged.match(/src\/Page\/.*\.elm/)
    );
  }

  /**
   * @param {string} pathname
   * @param {((value: any) => any) | null | undefined} onOk
   * @param {((reason: any) => PromiseLike<never>) | null | undefined} onErr
   */
  function runRenderThread(pathname, onOk, onErr) {
    let cleanUpThread = () => {};
    return new Promise(async (resolve, reject) => {
      const readyThread = await waitForThread();
      console.log(`Rendering ${pathname}`, readyThread.worker.threadId);
      cleanUpThread = () => {
        cleanUp(readyThread);
      };

      readyThread.ready = false;
      readyThread.worker.postMessage({
        mode: "dev-server",
        pathname,
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
      await runRenderThread(
        pathname,
        function (renderResult) {
          const is404 = renderResult.is404;
          switch (renderResult.kind) {
            case "json": {
              res.writeHead(is404 ? 404 : 200, {
                "Content-Type": "application/json",
              });
              res.end(renderResult.contentJson);
              break;
            }
            case "html": {
              res.writeHead(is404 ? 404 : 200, {
                "Content-Type": "text/html",
              });
              res.end(renderResult.htmlString);
              break;
            }
            case "api-response": {
              let mimeType = serveStatic.mime.lookup(pathname || "text/html");
              mimeType =
                mimeType === "application/octet-stream"
                  ? "text/html"
                  : mimeType;
              res.writeHead(renderResult.statusCode, {
                "Content-Type": mimeType,
              });
              res.end(renderResult.body);
              // TODO - if route is static, write file to api-route-cache/ directory
              // TODO - get 404 or other status code from elm-pages renderer
              break;
            }
          }
        },

        function (error) {
          console.log(restoreColor(error.errorsJson));

          if (req.url.includes("content.json")) {
            res.writeHead(500, { "Content-Type": "application/json" });
            res.end(JSON.stringify(error.errorsJson));
          } else {
            res.writeHead(500, { "Content-Type": "text/html" });
            res.end(errorHtml());
          }
        }
      );
    } catch (error) {
      console.log(restoreColor(error.errorsJson));

      if (req.url.includes("content.json")) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify(error.errorsJson));
      } else {
        res.writeHead(500, { "Content-Type": "text/html" });
        res.end(errorHtml());
      }
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
      threadReadyQueue.push(resolve);
      runPendingWork();
    });
  }

  function runPendingWork() {
    const readyThreads = pool.filter((thread) => thread.ready);
    readyThreads.forEach((readyThread) => {
      const startTask = threadReadyQueue.shift();
      if (startTask) {
        startTask(readyThread);
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
    <link rel="stylesheet" href="/style.css"></link>
    <style>
@keyframes lds-default {
    0%, 20%, 80%, 100% {
      transform: scale(1);
    }
    50% {
      transform: scale(1.5);
    }
  }
    </style>
    <!--<link rel="preload" href="/elm-pages.js" as="script"> -->
    <link rel="preload" href="/index.js" as="script">
    <!--<link rel="preload" href="/elm.js" as="script">-->
    <script src="/hmr.js" type="text/javascript"></script>
    <!--<script defer="defer" src="/elm.js" type="text/javascript"></script>-->
    <!--<script defer="defer" src="/elm-pages.js" type="module"></script>-->
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

module.exports = { start };
