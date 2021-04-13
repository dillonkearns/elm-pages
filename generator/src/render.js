// @ts-check

const cliVersion = require("../../package.json").version;
const path = require("path");
const seo = require("./seo-renderer.js");
const matter = require("gray-matter");
const globby = require("globby");
const mm = require("micromatch");
const fsPromises = require("fs").promises;

let foundErrors = false;
process.on("unhandledRejection", (error) => {
  console.error("@@@ UNHANDLED", error);
});

module.exports =
  /**
   *
   * @param {string} compiledElmPath
   * @param {string} path
   * @param {import('aws-lambda').APIGatewayProxyEvent} request
   * @returns
   */
  async function run(compiledElmPath, path, request) {
    XMLHttpRequest = require("xhr2");
    const result = await runElmApp(compiledElmPath, path, request);
    return result;
  };

/**
 * @param {string} compiledElmPath
 * @param {string} pagePath
 * @param {import('aws-lambda').APIGatewayProxyEvent} request
 * @returns {Promise<({ kind: 'json'; contentJson: string} | { kind: 'html'; htmlString: string })>}
 */
function runElmApp(compiledElmPath, pagePath, request) {
  return new Promise((resolve, reject) => {
    console.time(`renderer-${pagePath}`);
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
        request: modifiedRequest,
      },
    });

    app.ports.toJsPort.subscribe(async (/** @type { FromElm }  */ fromElm) => {
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "InitialData") {
        const args = fromElm.args[0];
        // const contentJson = args.pages["blog"];
        // resolve({
        //   kind: "json",
        //   contentJson: JSON.stringify({ staticData: contentJson }),
        // });
        // fs.writeFile(
        //   `dist/manifest.json`,
        //   JSON.stringify(generateManifest(fromElm.args[0].manifest))
        // );
        // generateFiles(fromElm.args[0].filesToGenerate);
      } else if (fromElm.tag === "PageProgress") {
        const args = fromElm.args[0];
        global.staticHttpCache = args.staticHttpCache;

        console.timeEnd(`renderer-${pagePath}`);
        if (isJson) {
          resolve({
            kind: "json",
            contentJson: JSON.stringify({ staticData: args.contentJson }),
          });
        } else {
          resolve(outputString(fromElm));
        }
      } else if (fromElm.tag === "ReadFile") {
        const filePath = fromElm.args[0];

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
          },
        });
      } else if (fromElm.tag === "Glob") {
        const globPattern = fromElm.args[0];
        const globResult = await globby(globPattern);
        const captures = globResult.map((result) => {
          return {
            captures: mm.capture(globPattern, result),
            fullPath: result,
          };
        });

        app.ports.fromJsPort.send({
          tag: "GotGlob",
          data: { pattern: globPattern, result: captures },
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
  const normalizedRoute = args.route.replace(/index$/, "");
  const contentJsonString = JSON.stringify(contentJson);

  return {
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
  /*html*/
  return `<!DOCTYPE html>
  <html lang="en">
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

    ${seo.toString(fromElm.head)}
    </head>
    <body>
      <div data-url="" display="none"></div>
      ${fromElm.html}
    </body>
  </html>
  `;
}
