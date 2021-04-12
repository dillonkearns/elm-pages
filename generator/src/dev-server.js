const path = require("path");
const fs = require("fs");
const chokidar = require("chokidar");
const compiledElmPath = path.join(process.cwd(), "elm-stuff/elm-pages/elm.js");
const renderer = require("../../generator/src/render");
const port = 1234;
const { spawnElmMake, compileElmForBrowser } = require("./compile-elm.js");
const http = require("http");
const codegen = require("./codegen.js");
const kleur = require("kleur");
const serveStatic = require("serve-static");
const connect = require("connect");

global.staticHttpCache = {};
let elmMakeRunning = true;

const serve = serveStatic("static/", { index: false });
const serveStaticCode = serveStatic(path.join(__dirname, "../static-code"), {});

const pathToClientElm = path.join(process.cwd(), "browser-elm.js");

// TODO check source-directories for what to watch?
const watcher = chokidar.watch(
  [path.join(process.cwd(), "src"), path.join(process.cwd(), "content")],
  { persistent: true, ignored: [/\.swp$/] }
);
let clientElmMakeProcess = compileElmForBrowser();
let pendingCliCompile = compileCliApp();

Promise.all([clientElmMakeProcess, pendingCliCompile])
  .then(() => {
    console.log("@@@ Done with both initial compilations");
    elmMakeRunning = false;
  })
  .catch(() => {
    elmMakeRunning = false;
  });

async function compileCliApp() {
  await spawnElmMake(
    "TemplateModulesBeta.elm",
    "elm.js",
    "elm-stuff/elm-pages"
  );
}

const app = connect()
  .use(timeMiddleware())
  .use(processRequest)
  .use(serveStaticCode)
  .use(serve);
http.createServer(app).listen(port);
/**
 * @param {http.IncomingMessage} request
 * @param {http.ServerResponse} response
 * @param {() => void} next
 */
async function processRequest(request, response, next) {
  if (request.url?.startsWith("/elm.js")) {
    try {
      const clientElmJs = await clientElmMakeProcess;
      response.writeHead(200, { "Content-Type": "text/javascript" });
      response.end(clientElmJs);
    } catch (elmCompilerError) {
      response.writeHead(500, { "Content-Type": "application/json" });
      response.end(elmCompilerError);
    }
  } else if (request.url?.startsWith("/stream")) {
    handleStream(response);
  } else if (
    request.url.includes("content.json") ||
    request.headers["sec-fetch-mode"] === "navigate"
  ) {
    handleNavigationRequest(request, response);
  } else {
    next();
  }
}

console.log(`Server listening at http://localhost:${port}`);

/**
 * @param {http.ServerResponse} res
 */
function handleStream(res) {
  res.writeHead(200, {
    Connection: "keep-alive",
    "Content-Type": "text/event-stream",
  });
  watcher.on("all", async function (eventName, pathThatChanged, stats) {
    console.log({ pathThatChanged, eventName });
    if (pathThatChanged.endsWith(".elm")) {
      if (elmMakeRunning) {
        console.log("@@@ ignoring because elmMakeRunning");
        return;
      } else {
        if (needToRerunCodegen(eventName, pathThatChanged)) {
          console.log("@@@ codegen");
          await codegen.generate();
        }
        elmMakeRunning = true;
        clientElmMakeProcess = compileElmForBrowser();
        pendingCliCompile = compileCliApp();
        Promise.all([clientElmMakeProcess, pendingCliCompile])
          .then(() => {
            console.log("@@@ Done with both compilations");
            elmMakeRunning = false;
          })
          .catch(() => {
            elmMakeRunning = false;
          });
        console.log("Pushing HMR event to client");
        res.write(`data: content.json\n\n`);
      }
    } else {
      console.log("Pushing HMR event to client");
      res.write(`data: content.json\n\n`);
    }
  });
}

/**
 * @param {string} pathThatChanged
 * @param {'add' | 'unlink' | 'addDir' | 'unlinkDir' | 'change'} eventName
 */
function needToRerunCodegen(eventName, pathThatChanged) {
  return (
    (eventName === "add" || eventName === "unlink") &&
    pathThatChanged.match(/src\/Template\/.*\.elm/)
  );
}

async function handleNavigationRequest(req, res) {
  if (req.url.endsWith(".ico") || req.url.endsWith("manifest.json")) {
    res.writeHead(404, {
      "Content-Type": "text/html",
    });
    res.end(`Not found.`);
  } else {
    try {
      await pendingCliCompile;
      const renderResult = await renderer(compiledElmPath, req.url, req);
      if (renderResult.kind === "json") {
        res.writeHead(200, {
          "Content-Type": "application/json",
        });
        res.end(renderResult.contentJson);
      } else {
        res.writeHead(200, {
          "Content-Type": "text/html",
        });
        res.end(renderResult.htmlString);
      }
    } catch (error) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify(error.errorsJson));
    }
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
  return url;
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
