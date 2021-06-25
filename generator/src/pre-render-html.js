const cliVersion = require("../../package.json").version;
const seo = require("./seo-renderer.js");
const elmPagesJsMinified = require("./elm-pages-js-minified.js");

/** @typedef { { head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */
/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

module.exports =
  /**
   * @param {Arg} fromElm
   * @param {string} contentJsonString
   * @param {boolean} devServer
   * @returns {string}
   */
  function wrapHtml(fromElm, contentJsonString, devServer) {
    const devServerOnly = (/** @type {string} */ devServerOnlyString) =>
      devServer ? devServerOnlyString : "";
    const seoData = seo.gather(fromElm.head);
    /*html*/
    return `<!DOCTYPE html>
  ${seoData.rootElement}
  <head>
    <link rel="stylesheet" href="/style.css">
    ${devServerOnly(devServerStyleTag())}
    <link rel="preload" href="/elm.js" as="script">
    <link rel="modulepreload" href="/index.js">
    ${devServerOnly(
      /* html */ `<script defer="defer" src="/hmr.js" type="text/javascript"></script>`
    )}
    <script defer="defer" src="/elm.js" type="text/javascript"></script>
    <base href="${baseRoute(fromElm.route)}">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <script type="module">
import userInit from"/index.js";
window.__elmPagesContentJson__ = ${contentJsonString}
${elmPagesJsMinified}
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
  };

/**
 * @param {string} route
 */
function baseRoute(route) {
  const cleanedRoute = cleanRoute(route);
  return cleanedRoute === "" ? "./" : pathToRoot(route);
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

function devServerStyleTag() {
  /*html*/
  return `<style>
@keyframes lds-default {
    0%, 20%, 80%, 100% {
      transform: scale(1);
    }
    50% {
      transform: scale(1.5);
    }
  }

#not-found-reason code {
  color: rgb(226, 0, 124);
}

#not-found-reason h1 {
  font-size: 26px;
  font-weight: bold;
  padding-bottom: 15px;
}

#not-found-reason a:hover {
  text-decoration: underline;
}
</style>`;
}
