const indexTemplate = require("./index-template.js");
const util = require("util");
const fs = require("./dir-helpers.js");
const path = require("path");
const seo = require("./seo-renderer.js");
const exec = util.promisify(require("child_process").exec);
const codegen = require("./codegen.js");
const generateManifest = require("./generate-manifest.js");

const DIR_PATH = path.join(process.cwd());
const OUTPUT_FILE_NAME = "elm.js";

let foundErrors = false;

const ELM_FILE_PATH = path.join(
  DIR_PATH,
  "./elm-stuff/elm-pages",
  OUTPUT_FILE_NAME
);

async function ensureRequiredDirs() {
  fs.tryMkdir(`dist`);
}

async function run() {
  await ensureRequiredDirs();
  XMLHttpRequest = require("xhr2");

  await codegen.generate();

  await compileCliApp();

  copyAssets();
  compileElm();

  runElmApp();
}

function runElmApp() {
  process.on("beforeExit", (code) => {
    if (foundErrors) {
      process.exit(1);
    } else {
      process.exit(0);
    }
  });
  process.on("unhandledRejection", (error) => {
    console.error(error);
    process.exit(1);
  });

  return new Promise((resolve, _) => {
    const mode /** @type { "dev" | "prod" } */ = "elm-to-html-beta";
    const staticHttpCache = {};
    const app = require(ELM_FILE_PATH).Elm.Main.init({
      flags: { secrets: process.env, mode, staticHttpCache },
    });

    app.ports.toJsPort.subscribe((/** @type { FromElm }  */ fromElm) => {
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "InitialData") {
        fs.writeFile(
          `dist/manifest.json`,
          JSON.stringify(generateManifest(fromElm.args[0].manifest))
        );
        generateFiles(fromElm.args[0].filesToGenerate);
      } else if (fromElm.tag === "PageProgress") {
        outputString(fromElm);
      } else if (fromElm.tag === "Errors") {
        console.error(fromElm.args[0]);
        foundErrors = true;
      } else {
        console.log(fromElm);
        throw "Unknown port tag.";
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
 * @param {string} elmPath
 */
async function elmToEsm(elmPath) {
  const elmEs3 = await fs.readFile(elmPath, "utf8");

  const elmEsm =
    "\n" +
    "const scope = {};\n" +
    elmEs3.replace("}(this));", "}(scope));") +
    "export const { Elm } = scope;\n" +
    "\n";

  await fs.writeFile(elmPath, elmEsm);
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
  // await fs.mkdir(`./dist/${normalizedRoute}`, { recursive: true });
  await fs.tryMkdir(`./dist/${normalizedRoute}`);
  fs.writeFile(`dist/${normalizedRoute}/index.html`, wrapHtml(args));
  fs.writeFile(
    `dist/${normalizedRoute}/content.json`,
    JSON.stringify(contentJson)
  );
}

async function compileElm() {
  const outputPath = `dist/main.js`;
  await shellCommand(
    `elm-optimize-level-2 src/Main.elm --output ${outputPath}`
  );
  await elmToEsm(path.join(process.cwd(), outputPath));
  runTerser(outputPath);
}

/**
 * @param {string} filePath
 */
async function runTerser(filePath) {
  await shellCommand(
    `npx terser ${filePath} --module --compress 'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe' | npx terser --module --mangle --output=${filePath}`
  );
}

async function copyAssets() {
  fs.writeFile("dist/index.js", indexTemplate);
  fs.copyFile("user-index.js", "dist/user-index.js");
  fs.copyFile("style.css", "dist/style.css");
  fs.copyDirFlat("static", "dist");
  fs.tryMkdir("dist/images");
  fs.copyDirNested("images", "dist/images");
}

async function compileCliApp() {
  await shellCommand(
    `cd ./elm-stuff/elm-pages && elm-optimize-level-2 ../../src/Main.elm --output elm.js`
  );
  const elmFileContent = await fs.readFile(ELM_FILE_PATH, "utf-8");
  await fs.writeFile(
    ELM_FILE_PATH,
    elmFileContent.replace(
      /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
      "return x"
    )
  );
}

run();

/**
 * @param {string} command
 */
async function shellCommand(command) {
  const output = await exec(command);
  if (output.stderr) {
    throw output.stderr;
  }
  return output;
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; body: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

/** @typedef {     
     {
        body: string;
        head: any[];
        errors: any[];
        contentJson: any[];
        html: string;
        route: string; }
    } Arg
*/

function wrapHtml(/** @type { Arg } */ fromElm) {
  /*html*/
  return `<!DOCTYPE html>
  <html lang="en">
  <head>
    <link rel="preload" href="content.json" as="fetch" crossorigin="">
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
    </script>
    <link rel="shortcut icon" href="https://res.cloudinary.com/dillonkearns/image/upload/w_64/v1602878565/Favicon_Dark_adgn6v.png">
    <link rel="icon" type="image/png" sizes="16x16" href="https://res.cloudinary.com/dillonkearns/image/upload/w_16/v1602878565/Favicon_Dark_adgn6v.png">
    <link rel="icon" type="image/png" sizes="32x32" href="https://res.cloudinary.com/dillonkearns/image/upload/w_32/v1602878565/Favicon_Dark_adgn6v.png">
    <link rel="icon" type="image/png" sizes="48x48" href="https://res.cloudinary.com/dillonkearns/image/upload/w_48/v1602878565/Favicon_Dark_adgn6v.png">
    <link rel="manifest" href="manifest.json">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="theme-color" content="#ffffff">
    <meta name="application-name" content="elm-pages docs">
    <link rel="apple-touch-icon" sizes="57x57" href="assets/apple-touch-icon-57x57.png">
    <link rel="apple-touch-icon" sizes="60x60" href="assets/apple-touch-icon-60x60.png">
    <link rel="apple-touch-icon" sizes="72x72" href="assets/apple-touch-icon-72x72.png">
    <link rel="apple-touch-icon" sizes="76x76" href="assets/apple-touch-icon-76x76.png">
    <link rel="apple-touch-icon" sizes="114x114" href="assets/apple-touch-icon-114x114.png">
    <link rel="apple-touch-icon" sizes="120x120" href="assets/apple-touch-icon-120x120.png">
    <link rel="apple-touch-icon" sizes="144x144" href="assets/apple-touch-icon-144x144.png">
    <link rel="apple-touch-icon" sizes="152x152" href="assets/apple-touch-icon-152x152.png">
    <link rel="apple-touch-icon" sizes="167x167" href="assets/apple-touch-icon-167x167.png">
    <link rel="apple-touch-icon" sizes="180x180" href="assets/apple-touch-icon-180x180.png">
    <link rel="apple-touch-icon" sizes="1024x1024" href="assets/apple-touch-icon-1024x1024.png">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">

    <meta name="apple-mobile-web-app-title" content="elm-pages">
    <script defer="defer" src="/main.js" type="module"></script>
    <script defer="defer" src="/index.js" type="module"></script>
    <link rel="stylesheet" href="/style.css"></link>
    <link rel="preload" href="/main.js" as="script">
    ${seo.toString(fromElm.head)}
    <body>
      <div data-url="" display="none"></div>
      ${fromElm.html}
    </body>
  </html>
  `;
}
