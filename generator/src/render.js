// @ts-check

const path = require("path");
const matter = require("gray-matter");
const globby = require("globby");
const fsPromises = require("fs").promises;
const preRenderHtml = require("./pre-render-html.js");
const { lookupOrPerform } = require("./request-cache.js");
const kleur = require("kleur");
const cookie = require("cookie-signature");
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
   * @param {{ method: string; hostname: string; query: Record<string, string | undefined>; headers: Record<string, string>; host: string; pathname: string; port: number | null; protocol: string; rawUrl: string; }} request
   * @param {(pattern: string) => void} addDataSourceWatcher
   * @param {boolean} hasFsAccess
   * @returns
   */
  async function run(
    basePath,
    elmModule,
    mode,
    path,
    request,
    addDataSourceWatcher,
    hasFsAccess
  ) {
    const { fs, resetInMemoryFs } = require("./request-cache-fs.js")(
      hasFsAccess
    );
    resetInMemoryFs();
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
      addDataSourceWatcher,
      fs,
      hasFsAccess
    );
    return result;
  };

/**
 * @param {string} basePath
 * @param {Object} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @param {{ method: string; hostname: string; query: string; headers: Object; host: string; pathname: string; port: string; protocol: string; rawUrl: string; }} request
 * @param {(pattern: string) => void} addDataSourceWatcher
 * @returns {Promise<({is404: boolean} & ( { kind: 'json'; contentJson: string} | { kind: 'html'; htmlString: string } | { kind: 'api-response'; body: string; }) )>}
 */
function runElmApp(
  basePath,
  elmModule,
  mode,
  pagePath,
  request,
  addDataSourceWatcher,
  fs,
  hasFsAccess
) {
  const isDevServer = mode !== "build";
  let patternsToWatch = new Set();
  let app = null;
  let killApp;
  return new Promise((resolve, reject) => {
    const isBytes = pagePath.match(/content\.dat\/?$/);
    const route = pagePath
      .replace(/content\.json\/?$/, "")
      .replace(/content\.dat\/?$/, "");

    const modifiedRequest = { ...request, path: route };
    // console.log("StaticHttp cache keys", Object.keys(global.staticHttpCache));
    app = elmModule.Elm.Main.init({
      flags: {
        secrets: process.env,
        staticHttpCache: global.staticHttpCache || {},
        mode,
        request: {
          payload: modifiedRequest,
          kind: "single-page",
          jsonOnly: !!isBytes,
        },
      },
    });

    killApp = () => {
      app.ports.toJsPort.unsubscribe(portHandler);
      app.ports.sendPageData.unsubscribe(portHandler);
      app.die();
      app = null;
      // delete require.cache[require.resolve(compiledElmPath)];
    };

    async function portHandler(/** @type { FromElm }  */ newThing) {
      let fromElm;
      let contentDatPayload;
      if ("oldThing" in newThing) {
        fromElm = newThing.oldThing;
        contentDatPayload = newThing.binaryPageData;
      } else {
        fromElm = newThing;
      }
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

        if (isBytes) {
          resolve({
            kind: "bytes",
            is404: false,
            contentJson: JSON.stringify({
              staticData: args.contentJson,
              is404: false,
            }),
            statusCode: args.statusCode,
            headers: args.headers,
            contentDatPayload,
          });
        } else {
          resolve(
            outputString(basePath, fromElm, isDevServer, contentDatPayload)
          );
        }
      } else if (fromElm.tag === "DoHttp") {
        const requestToPerform = fromElm.args[0];
        if (requestToPerform.url.startsWith("elm-pages-internal://")) {
          runInternalJob(
            app,
            mode,
            requestToPerform,
            fs,
            hasFsAccess,
            patternsToWatch
          );
        } else {
          runHttpJob(app, mode, requestToPerform, fs, hasFsAccess);
        }
      } else if (fromElm.tag === "Errors") {
        foundErrors = true;
        reject(fromElm.args[0].errorsJson);
      } else {
        console.log(fromElm);
      }
    }
    app.ports.toJsPort.subscribe(portHandler);
    app.ports.sendPageData.subscribe(portHandler);
  }).finally(() => {
    addDataSourceWatcher(patternsToWatch);
    killApp();
    killApp = null;
  });
}
/**
 * @param {string} basePath
 * @param {PageProgress} fromElm
 * @param {boolean} isDevServer
 */
async function outputString(
  basePath,
  /** @type { PageProgress } */ fromElm,
  isDevServer,
  contentDatPayload
) {
  const args = fromElm.args[0];
  let contentJson = {};
  contentJson["staticData"] = args.contentJson;
  contentJson["is404"] = args.is404;
  contentJson["path"] = args.route;
  contentJson["statusCode"] = args.statusCode;
  contentJson["headers"] = args.headers;
  const normalizedRoute = args.route.replace(/index$/, "");

  return {
    is404: args.is404,
    route: normalizedRoute,
    htmlString: preRenderHtml(
      basePath,
      args,
      contentJson,
      isDevServer,
      contentDatPayload
    ),
    contentJson: args.contentJson,
    statusCode: args.statusCode,
    headers: args.headers,
    kind: "html",
    contentDatPayload,
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
      await fsPromises.readFile(
        path.join(process.env.LAMBDA_TASK_ROOT || process.cwd(), filePath)
      )
    ).toString();
    const parsedFile = matter(fileContents);

    pendingDataSourceResponses.push(
      jsonResponse(
        {
          url: `file://${filePath}`,
          method: "GET",
          headers: [],
          body: { tag: "EmptyBody", args: [] },
        },
        {
          parsedFrontmatter: parsedFile.data,
          withoutFrontmatter: parsedFile.content,
          rawFile: fileContents,
          jsonFile: jsonOrNull(fileContents),
        }
      )
    );
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

async function runHttpJob(app, mode, requestToPerform, fs, hasFsAccess) {
  pendingDataSourceCount += 1;
  try {
    const responseFilePath = await lookupOrPerform(
      mode,
      requestToPerform,
      hasFsAccess
    );

    pendingDataSourceResponses.push({
      requestAndResponse: {
        request: requestToPerform,
        response: JSON.parse(
          (await fs.promises.readFile(responseFilePath, "utf8")).toString()
        ),
      },
      maybeBytes: null,
    });
  } catch (error) {
    sendError(app, error);
  } finally {
    pendingDataSourceCount -= 1;
    flushIfDone(app);
  }
}

function stringResponse(request, string) {
  return {
    requestAndResponse: {
      request,
      response: { bodyKind: "string", body: string },
    },
    maybeBytes: null,
  };
}
function jsonResponse(request, json) {
  return {
    requestAndResponse: { request, response: { bodyKind: "json", body: json } },
    maybeBytes: null,
  };
}

async function runInternalJob(
  app,
  mode,
  requestToPerform,
  fs,
  hasFsAccess,
  patternsToWatch
) {
  try {
    pendingDataSourceCount += 1;

    if (requestToPerform.url === "elm-pages-internal://read-file") {
      pendingDataSourceResponses.push(
        await readFileJobNew(requestToPerform, patternsToWatch)
      );
    } else if (requestToPerform.url === "elm-pages-internal://glob") {
      pendingDataSourceResponses.push(
        await runGlobNew(requestToPerform, patternsToWatch)
      );
    } else if (requestToPerform.url === "elm-pages-internal://env") {
      pendingDataSourceResponses.push(
        await runEnvJob(requestToPerform, patternsToWatch)
      );
    } else if (requestToPerform.url === "elm-pages-internal://encrypt") {
      pendingDataSourceResponses.push(
        await runEncryptJob(requestToPerform, patternsToWatch)
      );
    } else if (requestToPerform.url === "elm-pages-internal://decrypt") {
      pendingDataSourceResponses.push(
        await runDecryptJob(requestToPerform, patternsToWatch)
      );
    } else {
      throw `Unexpected internal DataSource request format: ${kleur.yellow(
        JSON.stringify(2, null, requestToPerform)
      )}`;
    }
  } catch (error) {
    throw error;
  } finally {
    pendingDataSourceCount -= 1;
    flushIfDone(app);
  }
}

async function readFileJobNew(req, patternsToWatch) {
  const filePath = req.body.args[1];
  try {
    patternsToWatch.add(filePath);

    const fileContents = (
      await fsPromises.readFile(
        path.join(process.env.LAMBDA_TASK_ROOT || process.cwd(), filePath)
      )
    ).toString();
    const parsedFile = matter(fileContents);

    return jsonResponse(req, {
      parsedFrontmatter: parsedFile.data,
      withoutFrontmatter: parsedFile.content,
      rawFile: fileContents,
      jsonFile: jsonOrNull(fileContents),
    });
  } catch (error) {
    throw {
      title: "DataSource.File Error",
      message: `A DataSource.File read failed because I couldn't find this file: ${kleur.yellow(
        filePath
      )}\n${kleur.red(error.toString())}`,
    };
  }
}

async function runGlobNew(req, patternsToWatch) {
  try {
    const matchedPaths = await globby(req.body.args[1]);
    patternsToWatch.add(req.body.args[1]);

    return jsonResponse(req, matchedPaths);
  } catch (e) {
    console.log(`Error performing glob '${JSON.stringify(req.body)}'`);
    throw e;
  }
}

async function runEnvJob(req, patternsToWatch) {
  try {
    const expectedEnv = req.body.args[0];
    return jsonResponse(req, process.env[expectedEnv] || null);
  } catch (e) {
    console.log(`Error performing env '${JSON.stringify(req.body)}'`);
    throw e;
  }
}
async function runEncryptJob(req, patternsToWatch) {
  try {
    return jsonResponse(
      req,
      cookie.sign(
        JSON.stringify(req.body.args[0].values, null, 0),
        req.body.args[0].secret
      )
    );
  } catch (e) {
    throw {
      title: "DataSource Encrypt Error",
      message:
        e.toString() + e.stack + "\n\n" + JSON.stringify(rawRequest, null, 2),
    };
  }
}
async function runDecryptJob(req, patternsToWatch) {
  try {
    // TODO if unsign returns `false`, need to have an `Err` in Elm because decryption failed
    const signed = tryDecodeCookie(
      req.body.args[0].input,
      req.body.args[0].secrets
    );

    return jsonResponse(req, JSON.parse(signed || "null"));
  } catch (e) {
    throw {
      title: "DataSource Decrypt Error",
      message:
        e.toString() + e.stack + "\n\n" + JSON.stringify(rawRequest, null, 2),
    };
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
  app.ports.gotBatchSub.send(temp);
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
        url: `glob://${globPattern}`,
        method: "GET",
        headers: [],
        body: { tag: "EmptyBody", args: [] },
      },
      response: jsonResponse(matchedPaths),
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
function tryDecodeCookie(input, secrets) {
  if (secrets.length > 0) {
    const signed = cookie.unsign(input, secrets[0]);
    if (signed) {
      return signed;
    } else {
      return tryDecodeCookie(input, secrets.slice(1));
    }
  } else {
    return null;
  }
}
