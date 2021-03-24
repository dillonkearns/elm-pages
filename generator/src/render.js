// @ts-check

const cliVersion = require("../../package.json").version;
const fs = require("./dir-helpers.js");
const path = require("path");
const seo = require("./seo-renderer.js");
const spawnCallback = require("cross-spawn").spawn;

const OUTPUT_FILE_NAME = "elm.js";
const debug = false;

let foundErrors = false;
process.on("unhandledRejection", (error) => {
  console.error(error);
  process.exit(1);
});

module.exports = async function run() {
  XMLHttpRequest = require("xhr2");
  console.log("RENDER NEW");
  const result = await runElmApp();
  return result;
};

function runElmApp() {
  process.on("beforeExit", (code) => {
    if (foundErrors) {
      process.exit(1);
    } else {
      process.exit(0);
    }
  });

  return new Promise((resolve, _) => {
    const ELM_FILE_PATH = path.join(process.cwd(), "elm-pages-cli.js");
    const mode /** @type { "dev" | "prod" } */ = "elm-to-html-beta";
    const staticHttpCache = {};
    const app = require(ELM_FILE_PATH).Elm.Main.init({
      flags: { secrets: process.env, mode, staticHttpCache },
    });

    app.ports.toJsPort.subscribe((/** @type { FromElm }  */ fromElm) => {
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "PageProgress") {
        resolve(outputString(fromElm));
      } else if (fromElm.tag === "Errors") {
        console.error(fromElm.args[0]);
        foundErrors = true;
      } else {
        console.log(fromElm);
      }
    });
  });
}

/**
 * @param {{ path: string; content: string; }[]} filesToGenerate
 */
async function generateFiles(filesToGenerate) {
  filesToGenerate.forEach(async ({ path: pathToGenerate, content }) => {
    const fullPath = `dist/${pathToGenerate}`;
    console.log(`Generating file /${pathToGenerate}`);
    await fs.tryMkdir(path.dirname(fullPath));
    fs.writeFile(fullPath, content);
  });
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
  console.log(`Pre-rendered /${args.route}`);
  let contentJson = {};
  contentJson["body"] = args.body;

  contentJson["staticData"] = args.contentJson;
  const normalizedRoute = args.route.replace(/index$/, "");
  const contentJsonString = JSON.stringify(contentJson);

  return {
    route: normalizedRoute,
    htmlString: wrapHtml(args, contentJsonString),
  };
}

function spawnElmMake(elmEntrypointPath, outputPath, cwd) {
  return new Promise((resolve, reject) => {
    const fullOutputPath = cwd ? path.join(cwd, outputPath) : outputPath;
    if (fs.existsSync(fullOutputPath)) {
      fs.rmSync(fullOutputPath, {
        force: true /* ignore errors if file doesn't exist */,
      });
    }
    const subprocess = runElm(elmEntrypointPath, outputPath, cwd);

    subprocess.on("close", (code) => {
      const fileOutputExists = fs.existsSync(fullOutputPath);
      if (code == 0 && fileOutputExists) {
        resolve();
      } else {
        reject();
        process.exit(1);
      }
    });
  });
}

/**
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string} cwd
 */
function runElm(elmEntrypointPath, outputPath, cwd) {
  if (debug) {
    return spawnCallback(
      `elm`,
      ["make", elmEntrypointPath, "--output", outputPath, "--debug"],
      {
        // ignore stdout
        stdio: ["inherit", "ignore", "inherit"],
        cwd: cwd,
      }
    );
  } else {
    return spawnCallback(
      `elm-optimize-level-2`,
      [elmEntrypointPath, "--output", outputPath],
      {
        // ignore stdout
        stdio: ["inherit", "ignore", "inherit"],
        cwd: cwd,
      }
    );
  }
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; body: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

/** @typedef {     { body: string; head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */

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
    <link rel="preload" href="content.json" as="fetch" crossorigin="">
    <link rel="stylesheet" href="/style.css"></link>
    <link rel="preload" href="/elm-pages.js" as="script">
    <link rel="preload" href="/index.js" as="script">
    <link rel="preload" href="/elm.js" as="script">
    <link rel="preload" href="/elm.js" as="script">
    <script defer="defer" src="/elm.js" type="module"></script>
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
    const contentJson = ${contentJsonString}
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
