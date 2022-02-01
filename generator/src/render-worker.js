const renderer = require("../../generator/src/render");
const path = require("path");
const fs = require("./dir-helpers.js");
const compiledElmPath = path.join(process.cwd(), "elm-stuff/elm-pages/elm.js");
const { parentPort, threadId, workerData } = require("worker_threads");
let Elm;

global.staticHttpCache = {};

async function run({ mode, pathname, serverRequest }) {
  console.time(`${threadId} ${pathname}`);
  try {
    const renderResult = await renderer(
      workerData.basePath,
      requireElm(mode),
      mode,
      pathname,
      serverRequest,
      function (patterns) {
        if (mode === "dev-server" && patterns.size > 0) {
          parentPort.postMessage({ tag: "watch", data: [...patterns] });
        }
      },
      true
    );

    if (mode === "dev-server") {
      parentPort.postMessage({ tag: "done", data: renderResult });
    } else if (mode === "build") {
      console.log("@@@renderResult", renderResult);
      outputString(renderResult, pathname);
    } else {
      throw `Unknown mode ${mode}`;
    }
  } catch (error) {
    if (error.errorsJson) {
      parentPort.postMessage({ tag: "error", data: error.errorsJson });
    } else {
      parentPort.postMessage({ tag: "error", data: error });
    }
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
  console.log("@@@build fromElm", Object.keys(fromElm));
  switch (fromElm.kind) {
    case "html": {
      const args = fromElm;
      const normalizedRoute = args.route.replace(/index$/, "");
      await fs.tryMkdir(`./dist/${normalizedRoute}`);
      const contentJsonString = JSON.stringify({
        is404: args.is404,
        staticData: args.contentJson,
        path: args.route,
      });
      fs.writeFileSync(`dist/${normalizedRoute}/index.html`, args.htmlString);
      fs.writeFileSync(
        `dist/${normalizedRoute}/content.json`,
        contentJsonString
      );
      console.log(
        "Buffer thing",
        args.contentBytes && Buffer.from(args.contentBytes.buffer)
      );
      args.contentBytes &&
        fs.writeFileSync(
          `dist/${normalizedRoute}/content.dat`,
          Buffer.from(args.contentBytes.buffer)
        );
      parentPort.postMessage({ tag: "done" });
      break;
    }
    case "api-response": {
      const body = fromElm.body.body;
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
