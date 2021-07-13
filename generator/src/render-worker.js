const renderer = require("../../generator/src/render");
const path = require("path");
const fs = require("./dir-helpers.js");
const compiledElmPath = path.join(process.cwd(), "elm-stuff/elm-pages/elm.js");
const { parentPort, threadId } = require("worker_threads");
let Elm;

global.staticHttpCache = {};

async function run({ mode, pathname }) {
  console.time(`${threadId} ${pathname}`);
  try {
    const req = null;
    const renderResult = await renderer(
      requireElm(mode),
      mode,
      pathname,
      req,
      function (patterns) {
        if (mode === "dev-server" && patterns.size > 0) {
          parentPort.postMessage({ tag: "watch", data: [...patterns] });
        }
      }
    );

    if (mode === "dev-server") {
      parentPort.postMessage({ tag: "done", data: renderResult });
    } else if (mode === "build") {
      outputString(renderResult, pathname);
    } else {
      throw `Unknown mode ${mode}`;
    }
  } catch (error) {
    parentPort.postMessage({ tag: "error", data: error });
  }
  console.timeEnd(`${threadId} ${pathname}`);
}

function requireElm(mode) {
  if (mode === "build") {
    if (!Elm) {
      const warnOriginal = console.warn;
      console.warn = function () {};

      Elm = require(compiledElmPath);
      console.warn = warnOriginal;
    }
    return Elm;
  } else {
    delete require.cache[require.resolve(compiledElmPath)];
    return require(compiledElmPath);
  }
}

async function outputString(
  /** @type { { kind: 'page'; data: PageProgress } | { kind: 'api'; data: Object }  } */ fromElm,
  /** @type string */ pathname
) {
  switch (fromElm.kind) {
    case "html": {
      const args = fromElm;
      console.log(`Pre-rendered /${args.route}`);
      const normalizedRoute = args.route.replace(/index$/, "");
      await fs.tryMkdir(`./dist/${normalizedRoute}`);
      const contentJsonString = JSON.stringify({
        is404: args.is404,
        staticData: args.contentJson,
      });
      fs.writeFileSync(`dist/${normalizedRoute}/index.html`, args.htmlString);
      fs.writeFileSync(
        `dist/${normalizedRoute}/content.json`,
        contentJsonString
      );
      // parentPort.postMessage({ tag: "done" });
      parentPort.postMessage({ tag: "done" });
      break;
    }
    case "api-response": {
      const body = fromElm.body;
      console.log(`Generated ${pathname}`);
      fs.writeFileSyncSafe(path.join("dist", pathname), body);
      if (pathname === "/all-paths.json") {
        parentPort.postMessage({ tag: "all-paths", data: body });
      } else {
        parentPort.postMessage({ tag: "done" });
      }

      break;
    }
  }
}

parentPort.on("message", run);

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */
