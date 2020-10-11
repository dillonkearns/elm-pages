const fs = require("fs");
const path = require("path");
const seo = require("./seo-renderer.js");

async function run() {
  XMLHttpRequest = require("xhr2");

  const DIR_PATH = path.join(process.cwd());
  const OUTPUT_FILE_NAME = "elm.js";

  const ELM_FILE_PATH = path.join(
    DIR_PATH,
    "./elm-stuff/elm-pages",
    OUTPUT_FILE_NAME
  );
  const util = require("util");
  const exec = util.promisify(require("child_process").exec);

  const output = await exec(
    "cd ./elm-stuff/elm-pages && elm-optimize-level-2 ../../src/Main.elm --output elm.js"
    // "cd ./elm-stuff/elm-pages && elm make ../../src/Main.elm --output elm.js"
  );
  if (output.stderr) {
    // console.error("Error", `${output.stdout}`);
    throw output.stderr;
  }
  console.log("shell", `${output.stdout}`);

  const output2 = await exec(
    `elm-optimize-level-2 src/Main.elm --output dist/main.js && terser dist/main.js --compress 'pure_funcs="F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9",pure_getters,keep_fargs=false,unsafe_comps,unsafe' | terser --mangle --output=dist/main.js`
    // "cd ./elm-stuff/elm-pages && elm make ../../src/Main.elm --output elm.js"
  );
  if (output2.stderr) {
    // console.error("Error", `${output.stdout}`);
    throw output2.stderr;
  }
  console.log("shell", `${output2.stdout}`);

  const elmFileContent = fs.readFileSync(ELM_FILE_PATH, "utf-8");
  fs.writeFileSync(
    ELM_FILE_PATH,
    elmFileContent.replace(
      /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
      "return x"
    )
  );

  function runElmApp() {
    return new Promise((resolve, _) => {
      const mode /** @type { "dev" | "prod" } */ = "elm-to-html-beta";
      const staticHttpCache = {};
      const app = require(ELM_FILE_PATH).Elm.Main.init({
        flags: { secrets: process.env, mode, staticHttpCache },
      });

      app.ports.toJsPort.subscribe((
        /** @type { { head: SeoTag[], allRoutes: string[], html: string } }  */ fromElm
      ) => {
        resolve(fromElm);
      });
    });
  }
  const value = await runElmApp();
  outputString(value);
  // console.log("Got value", value);
}

function outputString(/** @type { Object } */ fromElm) {
  fs.writeFileSync("dist/index.html", wrapHtml(fromElm));
  let contentJson = {};
  contentJson["body"] = "Hello!";
  contentJson["staticData"] = fromElm.contentJson;
  fs.writeFileSync("dist/content.json", JSON.stringify(contentJson));
}
run();

function wrapHtml(/** @type { Object } */ fromElm) {
  /*html*/
  return `<!DOCTYPE html>
  <html lang="en">
  <head>
    <link rel="preload" href="content.json" as="fetch" crossorigin="">
    <base href="./">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <script>if ("serviceWorker" in navigator) {
      window.addEventListener("load", () => {
        navigator.serviceWorker.register("service-worker.js");
      });
    } else {
      console.log("No service worker registered.");
    }</script>
    <link rel="shortcut icon" href="assets/favicon.ico">
    <link rel="icon" type="image/png" sizes="16x16" href="assets/favicon-16x16.png">
    <link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32x32.png">
    <link rel="icon" type="image/png" sizes="48x48" href="assets/favicon-48x48.png">
    <link rel="manifest" href="assets/manifest.json">
    <meta name="mobile-web-app-capable" content="yes"><meta name="theme-color" content="#ffffff"><meta name="application-name" content="elm-pages docs"><link rel="apple-touch-icon" sizes="57x57" href="assets/apple-touch-icon-57x57.png"><link rel="apple-touch-icon" sizes="60x60" href="assets/apple-touch-icon-60x60.png"><link rel="apple-touch-icon" sizes="72x72" href="assets/apple-touch-icon-72x72.png"><link rel="apple-touch-icon" sizes="76x76" href="assets/apple-touch-icon-76x76.png"><link rel="apple-touch-icon" sizes="114x114" href="assets/apple-touch-icon-114x114.png"><link rel="apple-touch-icon" sizes="120x120" href="assets/apple-touch-icon-120x120.png"><link rel="apple-touch-icon" sizes="144x144" href="assets/apple-touch-icon-144x144.png"><link rel="apple-touch-icon" sizes="152x152" href="assets/apple-touch-icon-152x152.png"><link rel="apple-touch-icon" sizes="167x167" href="assets/apple-touch-icon-167x167.png"><link rel="apple-touch-icon" sizes="180x180" href="assets/apple-touch-icon-180x180.png"><link rel="apple-touch-icon" sizes="1024x1024" href="assets/apple-touch-icon-1024x1024.png"><meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">

    <meta name="apple-mobile-web-app-title" content="elm-pages">
    <script defer="defer" src="main.js"></script>
    <script defer="defer" src="index.js" type="module"></script>
    <link rel="preload" href="main.js" as="script">
    ${seo.toString(fromElm.head)}
    <body>
      ${fromElm.html}
    </body>
  </html>
  `;
}
