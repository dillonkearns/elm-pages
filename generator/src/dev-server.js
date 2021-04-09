const path = require("path");
const fs = require("fs");
const chokidar = require("chokidar");
const compiledElmPath = path.join(process.cwd(), "elm-stuff/elm-pages/elm.js");
const elmPagesIndexFileContents = require("./index-template.js");
const renderer = require("../../generator/src/render");
const port = 1234;
const { spawnElmMake } = require("./compile-elm.js");
const http = require("http");
const fsPromises = fs.promises;
const codegen = require("./codegen.js");
const kleur = require("kleur");

const { inject } = require("elm-hot");

const pathToClientElm = path.join(process.cwd(), "browser-elm.js");
/** @type {Record<string, string>} */
const translations = {
  "/style.css": "/beta-style.css",
  "/index.js": "/beta-index.js",
};

// TODO check source-directories for what to watch?
const watcher = chokidar.watch(
  [path.join(process.cwd(), "src"), path.join(process.cwd(), "content")],
  { persistent: true }
);
let clientElmMakeProcess = spawnElmMake(
  "gen/TemplateModulesBeta.elm",
  pathToClientElm
);
let pendingCliCompile = compileCliApp();

async function compileCliApp() {
  await codegen.generate();
  await spawnElmMake(
    "TemplateModulesBeta.elm",
    "elm.js",
    "elm-stuff/elm-pages"
  );
}

http
  .createServer(function (request, response) {
    timeMiddleware(request, response);
    processRequest(request, response);
  })
  .listen(port);

async function processRequest(request, response) {
  if (request.url?.startsWith("/elm.js")) {
    try {
      await clientElmMakeProcess;
      response.writeHead(200, { "Content-Type": "text/javascript" });
      response.end(
        inject(fs.readFileSync(pathToClientElm, { encoding: "utf8" }))
      );
    } catch (elmCompilerError) {
      response.writeHead(500, { "Content-Type": "application/json" });
      response.end(elmCompilerError);
    }
  } else if (request.url?.startsWith("/stream")) {
    handleStream(response);
  } else {
    // console.log(request.headers);
    if (
      request.url.includes("content.json") ||
      request.headers["sec-fetch-mode"] === "navigate"
    ) {
      handleNavigationRequest(request, response);
    } else {
      const staticFile = await lookupStaticFile(request);
      if (staticFile) {
        response.writeHead(200, { "Content-Type": staticFile.contentType });
        response.end(staticFile.content, "utf-8");
      } else {
        response.writeHead(404);
        response.end();
      }
    }
  }
}

console.log(`Server listening at http://localhost:${port}`);

/**
 * @param {http.IncomingMessage} request
 * @returns {Promise<{ content: string; contentType: string; } | null>  }
 */
async function lookupStaticFile(request) {
  if (request.url === "/elm-pages.js") {
    return {
      content: elmPagesIndexFileContents,
      contentType: "text/javascript",
    };
  }
  const translated = translations[`${request.url}`];
  const imageOrStaticPath = request.url?.startsWith("/images/")
    ? request.url
    : `/static${request.url}`;
  const filePath = "." + (translated || imageOrStaticPath);
  return await fileContentWithType(filePath);
}

function handleStream(res) {
  res.writeHead(200, {
    Connection: "keep-alive",
    "Content-Type": "text/event-stream",
  });

  watcher.on("change", async function (pathThatChanged, stats) {
    console.log({ pathThatChanged, stats });
    if (pathThatChanged.endsWith(".elm")) {
      clientElmMakeProcess = spawnElmMake(
        "gen/TemplateModulesBeta.elm",
        pathToClientElm
      );
      pendingCliCompile = compileCliApp();
      console.log("Pushing HMR event to client");
      res.write(`data: content.json\n\n`);
    } else {
      console.log("Pushing HMR event to client");
      res.write(`data: content.json\n\n`);
    }
  });
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

/** @type {Record<string, string>} */
const mimeTypes = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".wav": "audio/wav",
  ".mp4": "video/mp4",
  ".woff": "application/font-woff",
  ".ttf": "application/font-ttf",
  ".eot": "application/vnd.ms-fontobject",
  ".otf": "application/font-otf",
  ".wasm": "application/wasm",
};

/**
 * @param {string} filePath
 */
async function fileContentWithType(filePath) {
  if (!fs.existsSync(path.join(process.cwd(), filePath))) {
    console.log(`Short circuiting ${filePath}`);
    return null;
  } else {
    var extname = String(path.extname(filePath)).toLowerCase();
    var contentType = mimeTypes[extname] || "application/octet-stream";
    try {
      return {
        content: (
          await fsPromises.readFile(path.join(process.cwd(), filePath))
        ).toString(),
        contentType,
      };
    } catch (error) {
      console.log({ error });
      return null;
    }
  }
}

/**
 *
 * @param {*} root
 */
function timeMiddleware(req, res) {
  const start = Date.now();
  const end = res.end;
  res.end = (...args) => {
    logTime(`${timeFrom(start)} ${prettifyUrl(req.url)}`);
    return end.call(res, ...args);
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
