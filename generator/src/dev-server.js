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
const generatedFilesDirectory = "elm-stuff/elm-pages/generated-files";
fs.mkdirSync(generatedFilesDirectory, { recursive: true });
const serveGeneratedFiles = serveStatic(generatedFilesDirectory, {
  index: false,
});
const serveStaticCode = serveStatic(path.join(__dirname, "../static-code"), {});
/** @type {{ id: number, response: http.ServerResponse }[]} */
let clients = [];

// TODO check source-directories for what to watch?
const watcher = chokidar.watch(["elm.json"], {
  persistent: true,
  ignored: [/\.swp$/],
  ignoreInitial: true,
});
watchElmSourceDirs();
let clientElmMakeProcess = compileElmForBrowser();
let pendingCliCompile = compileCliApp();

Promise.all([clientElmMakeProcess, pendingCliCompile])
  .then(() => {
    console.log("Dev server ready");
    elmMakeRunning = false;
  })
  .catch(() => {
    elmMakeRunning = false;
  });

function watchElmSourceDirs() {
  console.log("elm.json changed - reloading watchers");
  watcher.removeAllListeners();
  const sourceDirs = JSON.parse(fs.readFileSync("./elm.json").toString())[
    "source-directories"
  ];
  console.log("Watching...", { sourceDirs });
  watcher.add(sourceDirs);
}

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
  .use(serveGeneratedFiles)
  .use(serve);
http.createServer(app).listen(port);
/**
 * @param {http.IncomingMessage} request
 * @param {http.ServerResponse} response
 * @param {connect.NextHandleFunction} next
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
    handleStream(request, response);
  } else if (
    request.url.includes("content.json") ||
    request.headers["sec-fetch-mode"] === "navigate"
  ) {
    handleNavigationRequest(request, response);
  } else {
    next();
  }
}

console.log(`elm-pages dev server running at http://localhost:${port}`);

watcher.on("all", async function (eventName, pathThatChanged) {
  console.log({ pathThatChanged });
  if (pathThatChanged === "elm.json") {
    watchElmSourceDirs();
  } else if (pathThatChanged.endsWith(".elm")) {
    if (elmMakeRunning) {
    } else {
      if (needToRerunCodegen(eventName, pathThatChanged)) {
        await codegen.generate();
      }
      elmMakeRunning = true;
      clientElmMakeProcess = compileElmForBrowser();
      pendingCliCompile = compileCliApp();
      let timestamp = Date.now();

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
    const changedPathRelative = path.relative(process.cwd(), pathThatChanged);

    Object.keys(global.staticHttpCache).forEach((dataSourceKey) => {
      if (dataSourceKey.includes(`file://${changedPathRelative}`)) {
        delete global.staticHttpCache[dataSourceKey];
      }
    });
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
      const renderResult = await renderer(
        compiledElmPath,
        req.url,
        req,
        function (pattern) {
          console.log(`Watching data source ${pattern}`);
          watcher.add(pattern);
        }
      );
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
