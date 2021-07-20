// @ts-check

const path = require("path");
const matter = require("gray-matter");
const globby = require("globby");
const fsPromises = require("fs").promises;
const preRenderHtml = require("./pre-render-html.js");
const { lookupOrPerform } = require("./request-cache.js");
const kleur = require("kleur");
kleur.enabled = true;

process.on("unhandledRejection", (error) => {
  console.error(error);
});
let foundErrors;
let pendingDataSourceResponses;
let pendingDataSourceCount;

module.exports =
  /**
   *
   * @param {string} basePath
   * @param {Object} elmModule
   * @param {string} path
   * @param {import('aws-lambda').APIGatewayProxyEvent} request
   * @param {(pattern: string) => void} addDataSourceWatcher
   * @returns
   */
  async function run(
    basePath,
    elmModule,
    mode,
    path,
    request,
    addDataSourceWatcher
  ) {
    foundErrors = false;
    pendingDataSourceResponses = [];
    pendingDataSourceCount = 0;
    // since init/update are never called in pre-renders, and DataSource.Http is called using undici
    // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)
    XMLHttpRequest = {};
    const result = await runElmApp(
      basePath,
      elmModule,
      mode,
      path,
      request,
      addDataSourceWatcher
    );
    return result;
  };

/**
 * @param {string} basePath
 * @param {Object} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @param {import('aws-lambda').APIGatewayProxyEvent} request
 * @param {(pattern: string) => void} addDataSourceWatcher
 * @returns {Promise<({is404: boolean} & ( { kind: 'json'; contentJson: string} | { kind: 'html'; htmlString: string } | { kind: 'api-response'; body: string; }) )>}
 */
function runElmApp(
  basePath,
  elmModule,
  mode,
  pagePath,
  request,
  addDataSourceWatcher
) {
  let patternsToWatch = new Set();
  let app = null;
  let killApp;
  return new Promise((resolve, reject) => {
    const isJson = pagePath.match(/content\.json\/?$/);
    const route = pagePath.replace(/content\.json\/?$/, "");

    const modifiedRequest = { ...request, path: route };
    // console.log("StaticHttp cache keys", Object.keys(global.staticHttpCache));
    app = elmModule.Elm.TemplateModulesBeta.init({
      flags: {
        secrets: process.env,
        staticHttpCache: global.staticHttpCache || {},
        request: {
          payload: modifiedRequest,
          kind: "single-page",
          jsonOnly: !!isJson,
        },
      },
    });

    killApp = () => {
      app.ports.toJsPort.unsubscribe(portHandler);
      app.die();
      app = null;
      // delete require.cache[require.resolve(compiledElmPath)];
    };

    async function portHandler(/** @type { FromElm }  */ fromElm) {
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "ApiResponse") {
        const args = fromElm.args[0];
        if (mode === "build") {
          global.staticHttpCache = args.staticHttpCache;
        }

        resolve({
          kind: "api-response",
          is404: args.is404,
          statusCode: args.statusCode,
          body: args.body,
        });
      } else if (fromElm.tag === "PageProgress") {
        const args = fromElm.args[0];
        if (mode === "build") {
          global.staticHttpCache = args.staticHttpCache;
        }

        if (isJson) {
          resolve({
            kind: "json",
            is404: args.is404,
            contentJson: JSON.stringify({
              staticData: args.contentJson,
              is404: args.is404,
            }),
          });
        } else {
          resolve(outputString(basePath, fromElm));
        }
      } else if (fromElm.tag === "ReadFile") {
        const filePath = fromElm.args[0];
        try {
          patternsToWatch.add(filePath);

          runJob(app, filePath);
        } catch (error) {
          sendError(app, {
            title: "DataSource.File Error",
            message: `A DataSource.File read failed because I couldn't find this file: ${kleur.yellow(
              filePath
            )}`,
          });
        }
      } else if (fromElm.tag === "DoHttp") {
        const requestToPerform = fromElm.args[0];
        runHttpJob(app, mode, requestToPerform);
      } else if (fromElm.tag === "Glob") {
        const globPattern = fromElm.args[0];
        patternsToWatch.add(globPattern);
        runGlobJob(app, globPattern);
      } else if (fromElm.tag === "Errors") {
        foundErrors = true;
        reject(fromElm.args[0]);
      } else {
        console.log(fromElm);
      }
    }
    app.ports.toJsPort.subscribe(portHandler);
  }).finally(() => {
    addDataSourceWatcher(patternsToWatch);
    killApp();
    killApp = null;
  });
}
/**
 * @param {string} basePath
 * @param {PageProgress} fromElm
 */
async function outputString(basePath, /** @type { PageProgress } */ fromElm) {
  const args = fromElm.args[0];
  let contentJson = {};
  contentJson["staticData"] = args.contentJson;
  contentJson["is404"] = args.is404;
  contentJson["path"] = args.route;
  const normalizedRoute = args.route.replace(/index$/, "");
  const contentJsonString = JSON.stringify(contentJson);

  return {
    is404: args.is404,
    route: normalizedRoute,
    htmlString: preRenderHtml(basePath, args, contentJsonString, true),
    contentJson: args.contentJson,
    kind: "html",
  };
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

/** @typedef { { head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */

/**
 * @param {string} string
 */
function jsonOrNull(string) {
  try {
    return JSON.parse(string);
  } catch (e) {
    return { invalidJson: e.toString() };
  }
}

async function runJob(app, filePath) {
  pendingDataSourceCount += 1;
  try {
    const fileContents = (
      await fsPromises.readFile(path.join(process.cwd(), filePath))
    ).toString();
    const parsedFile = matter(fileContents);

    pendingDataSourceResponses.push({
      request: {
        masked: {
          url: `file://${filePath}`,
          method: "GET",
          headers: [],
          body: { tag: "EmptyBody", args: [] },
        },
        unmasked: {
          url: `file://${filePath}`,
          method: "GET",
          headers: [],
          body: { tag: "EmptyBody", args: [] },
        },
      },
      response: JSON.stringify({
        parsedFrontmatter: parsedFile.data,
        withoutFrontmatter: parsedFile.content,
        rawFile: fileContents,
        jsonFile: jsonOrNull(fileContents),
      }),
    });
  } catch (e) {
    sendError(app, {
      title: "Error reading file",
      message: `A DataSource.File read failed because I couldn't find this file: ${kleur.yellow(
        filePath
      )}`,
    });
  } finally {
    pendingDataSourceCount -= 1;
    flushIfDone(app);
  }
}

async function runHttpJob(app, mode, requestToPerform) {
  pendingDataSourceCount += 1;
  try {
    const responseFilePath = await lookupOrPerform(
      mode,
      requestToPerform.unmasked
    );

    pendingDataSourceResponses.push({
      request: requestToPerform,
      response: (
        await fsPromises.readFile(responseFilePath, "utf8")
      ).toString(),
    });
  } catch (error) {
    sendError(app, error);
  } finally {
    pendingDataSourceCount -= 1;
    flushIfDone(app);
  }
}

async function runGlobJob(app, globPattern) {
  try {
    // if (pendingDataSourceCount > 0) {
    //   console.log(`Waiting for ${pendingDataSourceCount} pending data sources`);
    // }
    pendingDataSourceCount += 1;

    pendingDataSourceResponses.push(await globTask(globPattern));
  } catch (error) {
    console.log(`Error running glob pattern ${globPattern}`);
    throw error;
  } finally {
    pendingDataSourceCount -= 1;
    flushIfDone(app);
  }
}

function flushIfDone(app) {
  if (foundErrors) {
    pendingDataSourceResponses = [];
  } else if (pendingDataSourceCount === 0) {
    // console.log(
    //   `Flushing ${pendingDataSourceResponses.length} items in ${timeUntilThreshold}ms`
    // );

    flushQueue(app);
  }
}

function flushQueue(app) {
  const temp = pendingDataSourceResponses;
  pendingDataSourceResponses = [];
  // console.log("@@@ FLUSHING", temp.length);
  app.ports.fromJsPort.send({
    tag: "GotBatch",
    data: temp,
  });
}

/**
 * @param {string} filePath
 * @returns {Promise<Object>}
 */
async function readFileTask(app, filePath) {
  // console.log(`Read file ${filePath}`);
  try {
    const fileContents = (
      await fsPromises.readFile(path.join(process.cwd(), filePath))
    ).toString();
    // console.log(`DONE reading file ${filePath}`);
    const parsedFile = matter(fileContents);

    return {
      request: {
        masked: {
          url: `file://${filePath}`,
          method: "GET",
          headers: [],
          body: { tag: "EmptyBody", args: [] },
        },
        unmasked: {
          url: `file://${filePath}`,
          method: "GET",
          headers: [],
          body: { tag: "EmptyBody", args: [] },
        },
      },
      response: JSON.stringify({
        parsedFrontmatter: parsedFile.data,
        withoutFrontmatter: parsedFile.content,
        rawFile: fileContents,
        jsonFile: jsonOrNull(fileContents),
      }),
    };
  } catch (e) {
    sendError(app, {
      title: "Error reading file",
      message: `A DataSource.File read failed because I couldn't find this file: ${kleur.yellow(
        filePath
      )}`,
    });
  }
}

/**
 * @param {string} globPattern
 * @returns {Promise<Object>}
 */
async function globTask(globPattern) {
  try {
    const matchedPaths = await globby(globPattern);
    // console.log("Got glob path", matchedPaths);

    return {
      request: {
        masked: {
          url: `glob://${globPattern}`,
          method: "GET",
          headers: [],
          body: { tag: "EmptyBody", args: [] },
        },
        unmasked: {
          url: `glob://${globPattern}`,
          method: "GET",
          headers: [],
          body: { tag: "EmptyBody", args: [] },
        },
      },
      response: JSON.stringify(matchedPaths),
    };
  } catch (e) {
    console.log(`Error performing glob '${globPattern}'`);
    throw e;
  }
}

function requireUncached(mode, filePath) {
  if (mode === "dev-server") {
    // for the build command, we can skip clearing the cache because it won't change while the build is running
    // in the dev server, we want to clear the cache to get a the latest code each time it runs
    delete require.cache[require.resolve(filePath)];
  }
  return require(filePath);
}

/**
 * @param {{ ports: { fromJsPort: { send: (arg0: { tag: string; data: any; }) => void; }; }; }} app
 * @param {{ message: string; title: string; }} error
 */
function sendError(app, error) {
  foundErrors = true;

  app.ports.fromJsPort.send({
    tag: "BuildError",
    data: error,
  });
}
