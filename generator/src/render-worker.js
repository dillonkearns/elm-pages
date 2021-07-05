const renderer = require("../../generator/src/render");
const path = require("path");
const fs = require("./dir-helpers.js");
const compiledElmPath = path.join(process.cwd(), "elm-stuff/elm-pages/elm.js");
let Elm = require(compiledElmPath);
const { parentPort, threadId } = require("worker_threads");

global.staticHttpCache = {};

async function run({ mode, pathname }) {
  console.log("Run", { mode, pathname });
  console.time(`${threadId} ${pathname}`);
  const req = null;
  const renderResult = await renderer(
    Elm,
    pathname,
    req,
    function (pattern) {}
  );

  if (mode === "dev-server") {
    parentPort.postMessage(renderResult);
  } else if (mode === "build") {
    outputString(renderResult, pathname);
  } else {
    throw `Unknown mode ${mode}`;
  }
  console.timeEnd(`${threadId} ${pathname}`);
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
      parentPort.postMessage("Success");
      break;
    }
    case "api-response": {
      const body = fromElm.body;
      console.log(`Generated ${pathname}`);
      fs.writeFileSync(path.join("dist", pathname), body);
      if (pathname === "/all-paths.json") {
        parentPort.postMessage(body);
      } else {
        parentPort.postMessage("Success");
      }

      break;
    }
  }
}

parentPort.on("message", run);

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */
