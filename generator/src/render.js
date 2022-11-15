// @ts-check

const path = require("path");
const mm = require("micromatch");
const matter = require("gray-matter");
const globby = require("globby");
const fsPromises = require("fs").promises;
const preRenderHtml = require("./pre-render-html.js");
const { lookupOrPerform } = require("./request-cache.js");
const kleur = require("kleur");
const cookie = require("cookie-signature");
const { compatibilityKey } = require("../compatibility-key.js");
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
    portsFile,
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
    // since init/update are never called in pre-renders, and DataSource.Http is called using pure NodeJS HTTP fetching
    // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)
    XMLHttpRequest = {};
    const result = await runElmApp(
      portsFile,
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
  portsFile,
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
        mode,
        compatibilityKey,
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
        if (
          requestToPerform.url !== "elm-pages-internal://port" &&
          requestToPerform.url.startsWith("elm-pages-internal://")
        ) {
          runInternalJob(
            app,
            mode,
            requestToPerform,
            fs,
            hasFsAccess,
            patternsToWatch
          );
        } else {
          runHttpJob(
            portsFile,
            app,
            mode,
            requestToPerform,
            fs,
            hasFsAccess,
            fromElm.args[1]
          );
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
    try {
      killApp();
      killApp = null;
    } catch (error) {}
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
    htmlString: preRenderHtml.wrapHtml(basePath, args, contentDatPayload),
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

async function runHttpJob(
  portsFile,
  app,
  mode,
  requestToPerform,
  fs,
  hasFsAccess,
  useCache
) {
  pendingDataSourceCount += 1;
  try {
    const responseFilePath = await lookupOrPerform(
      portsFile,
      mode,
      requestToPerform,
      hasFsAccess,
      useCache
    );

    pendingDataSourceResponses.push({
      request: requestToPerform,
      response: JSON.parse(
        (await fs.promises.readFile(responseFilePath, "utf8")).toString()
      ),
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
    request,
    response: { bodyKind: "string", body: string },
  };
}
function jsonResponse(request, json) {
  return {
    request,
    response: { bodyKind: "json", body: json },
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
    sendError(app, error);
  } finally {
    pendingDataSourceCount -= 1;
    flushIfDone(app);
  }
}

async function readFileJobNew(req, patternsToWatch) {
  const filePath = req.body.args[1];
  try {
    patternsToWatch.add(filePath);

    const fileContents = // TODO can I remove this hack?
      (
        await fsPromises.readFile(
          path.join(process.env.LAMBDA_TASK_ROOT || process.cwd(), filePath)
        )
      ).toString();
    const parsedFile = matter(fileContents);

    return jsonResponse(req, {
      parsedFrontmatter: parsedFile.data,
      withoutFrontmatter: parsedFile.content,
      rawFile: fileContents,
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
    const { pattern, options } = req.body.args[0];
    const matchedPaths = await globby(pattern, options);
    patternsToWatch.add(pattern);

    return jsonResponse(
      req,
      matchedPaths.map((fullPath) => {
        return {
          fullPath,
          captures: mm.capture(pattern, fullPath),
        };
      })
    );
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
