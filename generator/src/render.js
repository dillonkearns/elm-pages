// @ts-check

const path = require("path");
const matter = require("gray-matter");
const globby = require("globby");
const fsPromises = require("fs").promises;
const preRenderHtml = require("./pre-render-html.js");
const { lookupOrPerform } = require("./request-cache.js");

let foundErrors = false;
process.on("unhandledRejection", (error) => {
  console.error(error);
});

module.exports =
  /**
   *
   * @param {Object} elmModule
   * @param {string} path
   * @param {import('aws-lambda').APIGatewayProxyEvent} request
   * @param {(pattern: string) => void} addDataSourceWatcher
   * @returns
   */
  async function run(elmModule, path, request, addDataSourceWatcher) {
    // since init/update are never called in pre-renders, and DataSource.Http is called using undici
    // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)
    XMLHttpRequest = {};
    const result = await runElmApp(
      elmModule,
      path,
      request,
      addDataSourceWatcher
    );
    return result;
  };

/**
 * @param {Object} elmModule
 * @param {string} pagePath
 * @param {import('aws-lambda').APIGatewayProxyEvent} request
 * @param {(pattern: string) => void} addDataSourceWatcher
 * @returns {Promise<({is404: boolean} & ( { kind: 'json'; contentJson: string} | { kind: 'html'; htmlString: string } | { kind: 'api-response'; body: string; }) )>}
 */
function runElmApp(elmModule, pagePath, request, addDataSourceWatcher) {
  let patternsToWatch = new Set();
  let app = null;
  let killApp;
  return new Promise((resolve, reject) => {
    const isJson = pagePath.match(/content\.json\/?$/);
    const route = pagePath.replace(/content\.json\/?$/, "");

    const mode = "elm-to-html-beta";
    const modifiedRequest = { ...request, path: route };
    // console.log("StaticHttp cache keys", Object.keys(global.staticHttpCache));
    app = elmModule.Elm.TemplateModulesBeta.init({
      flags: {
        secrets: process.env,
        mode,
        staticHttpCache: global.staticHttpCache,
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
        global.staticHttpCache = args.staticHttpCache;

        resolve({
          kind: "api-response",
          is404: args.is404,
          statusCode: args.statusCode,
          body: args.body,
        });
      } else if (fromElm.tag === "PageProgress") {
        const args = fromElm.args[0];
        global.staticHttpCache = args.staticHttpCache;

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
          resolve(outputString(fromElm));
        }
      } else if (fromElm.tag === "ReadFile") {
        const filePath = fromElm.args[0];
        try {
          patternsToWatch.add(filePath);

          const fileContents = (
            await fsPromises.readFile(path.join(process.cwd(), filePath))
          ).toString();
          const parsedFile = matter(fileContents);
          app.ports.fromJsPort.send({
            tag: "GotFile",
            data: {
              filePath,
              parsedFrontmatter: parsedFile.data,
              withoutFrontmatter: parsedFile.content,
              rawFile: fileContents,
              jsonFile: jsonOrNull(fileContents),
            },
          });
        } catch (error) {
          app.ports.fromJsPort.send({
            tag: "BuildError",
            data: { filePath },
          });
        }
      } else if (fromElm.tag === "DoHttp") {
        const requestToPerform = fromElm.args[0];

        const responseFilePath = await lookupOrPerform(
          requestToPerform.unmasked
        );

        app.ports.fromJsPort.send({
          tag: "GotHttp",
          data: {
            request: requestToPerform,
            result: (
              await fsPromises.readFile(responseFilePath, "utf8")
            ).toString(),
          },
        });
      } else if (fromElm.tag === "Glob") {
        const globPattern = fromElm.args[0];
        patternsToWatch.add(globPattern);
        const matchedPaths = await globby(globPattern);

        app.ports.fromJsPort.send({
          tag: "GotGlob",
          data: { pattern: globPattern, result: matchedPaths },
        });
      } else if (fromElm.tag === "Port") {
        const portName = fromElm.args[0];
        console.log({ portName });

        app.ports.fromJsPort.send({
          tag: "GotPort",
          data: { portName, portResponse: "Hello from ports!" },
        });
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

async function outputString(/** @type { PageProgress } */ fromElm) {
  const args = fromElm.args[0];
  let contentJson = {};
  contentJson["staticData"] = args.contentJson;
  contentJson["is404"] = args.is404;
  const normalizedRoute = args.route.replace(/index$/, "");
  const contentJsonString = JSON.stringify(contentJson);

  return {
    is404: args.is404,
    route: normalizedRoute,
    htmlString: preRenderHtml(args, contentJsonString, true),
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
