// @ts-check

const cliVersion = require("../../package.json").version;
const path = require("path");
const seo = require("./seo-renderer.js");
const matter = require("gray-matter");
const globby = require("globby");
const fsPromises = require("fs").promises;

let foundErrors = false;
process.on("unhandledRejection", (error) => {
  console.error(error);
});

module.exports =
  /**
   *
   * @param {string} compiledElmPath
   * @param {string} path
   * @param {import('aws-lambda').APIGatewayProxyEvent} request
   * @param {(pattern: string) => void} addDataSourceWatcher
   * @returns
   */
  async function run(compiledElmPath, path, request, addDataSourceWatcher) {
    XMLHttpRequest = require("xhr2");
    const result = await runElmApp(
      compiledElmPath,
      path,
      request,
      addDataSourceWatcher
    );
    return result;
  };

/**
 * @param {string} compiledElmPath
 * @param {string} pagePath
 * @param {import('aws-lambda').APIGatewayProxyEvent} request
 * @param {(pattern: string) => void} addDataSourceWatcher
 * @returns {Promise<({ kind: 'json'; contentJson: string} | { kind: 'html'; htmlString: string } | { kind: 'api-response'; body: string; })>}
 */
function runElmApp(compiledElmPath, pagePath, request, addDataSourceWatcher) {
  return new Promise((resolve, reject) => {
    const isJson = pagePath.match(/content\.json\/?$/);
    const route = pagePath.replace(/content\.json\/?$/, "");

    const mode = "elm-to-html-beta";
    const modifiedRequest = { ...request, path: route };
    console.log("StaticHttp cache keys", Object.keys(global.staticHttpCache));
    const app = requireUncached(compiledElmPath).Elm.TemplateModulesBeta.init({
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

    app.ports.toJsPort.subscribe(async (/** @type { FromElm }  */ fromElm) => {
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "InitialData") {
        const args = fromElm.args[0];
        // console.log(`InitialData`, args);
        writeGeneratedFiles(args.filesToGenerate);
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

        // app.die();
        // delete require.cache[require.resolve(compiledElmPath)];
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
          addDataSourceWatcher(filePath);

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
      } else if (fromElm.tag === "Glob") {
        const globPattern = fromElm.args[0];
        addDataSourceWatcher(globPattern);
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
    });
  });
}

function requireUncached(modulePath) {
  delete require.cache[require.resolve(modulePath)];
  return require(modulePath);
}

/**
 * @param {string} route
 */
function cleanRoute(route) {
  return route.replace(/(^\/|\/$)/, "");
}

/**
 * @param {string} cleanedRoute
 */
function pathToRoot(cleanedRoute) {
  return cleanedRoute === ""
    ? cleanedRoute
    : cleanedRoute
        .split("/")
        .map((_) => "..")
        .join("/")
        .replace(/\.$/, "./");
}

/**
 * @param {string} route
 */
function baseRoute(route) {
  const cleanedRoute = cleanRoute(route);
  return cleanedRoute === "" ? "./" : pathToRoot(route);
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
    htmlString: wrapHtml(args, contentJsonString),
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
 * @param {Arg} fromElm
 * @param {string} contentJsonString
 * @returns
 */
function wrapHtml(fromElm, contentJsonString) {
  const seoData = seo.gather(fromElm.head);
  /*html*/
  return `<!DOCTYPE html>
  ${seoData.rootElement}
  <head>
    <link rel="stylesheet" href="/style.css"></link>
    <style>
@keyframes lds-default {
    0%, 20%, 80%, 100% {
      transform: scale(1);
    }
    50% {
      transform: scale(1.5);
    }
  }
    </style>
    <link rel="preload" href="/elm-pages.js" as="script">
    <link rel="preload" href="/index.js" as="script">
    <link rel="preload" href="/elm.js" as="script">
    <script defer="defer" src="/hmr.js" type="text/javascript"></script>
    <script defer="defer" src="/elm.js" type="text/javascript"></script>
    <script defer="defer" src="/elm-pages.js" type="module"></script>
    <base href="${baseRoute(fromElm.route)}">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <script>
    if ("serviceWorker" in navigator) {
      window.addEventListener("load", () => {
        navigator.serviceWorker.getRegistrations().then(function(registrations) {
          for (let registration of registrations) {
            registration.unregister()
          } 
        })
      });
    }
    window.__elmPagesContentJson__ = ${contentJsonString}
    </script>
    <title>${fromElm.title}</title>
    <meta name="generator" content="elm-pages v${cliVersion}">
    <link rel="manifest" href="manifest.json">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="theme-color" content="#ffffff">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">

    ${seoData.headTags}
    </head>
    <body>
      <div data-url="" display="none"></div>
      ${fromElm.html}
    </body>
  </html>
  `;
}

/**
 * @param {{ path: string; content: string; }[]} filesToGenerate
 */
async function writeGeneratedFiles(filesToGenerate) {
  await fsPromises.mkdir("elm-stuff/elm-pages/generated-files", {
    recursive: true,
  });
  await Promise.all(
    filesToGenerate.map((fileToGenerate) => {
      fsPromises.writeFile(
        path.join("elm-stuff/elm-pages/generated-files", fileToGenerate.path),
        fileToGenerate.content
      );
    })
  );
}

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
