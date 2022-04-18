/**
 * Welcome to Cloudflare Workers! This is your first worker.
 *
 * - Run `wrangler dev src/index.ts` in your terminal to start a development server
 * - Open a browser tab at http://localhost:8787/ to see your worker in action
 * - Run `wrangler publish src/index.ts --name my-worker` to publish your worker
 *
 * Learn more at https://developers.cloudflare.com/workers/
 */

// const compiledElmPath = "./dist/elm-pages-cli.js";
const compiledPortsFile = "../dist/port-data-source.mjs";
const Elm = require("../dist/elm-pages-cli.js");
const renderer = require("elm-pages/generator/src/render.js");
const preRenderHtml = require("elm-pages/generator/src/pre-render-html.js");

const htmlTemplate = `<!DOCTYPE html>
<!-- ROOT --><html lang="en">
  <head>
    <link rel="modulepreload" href="/assets/index.1764c0d6.js" />
    <script defer src="/elm.b49096aa.js" type="text/javascript"></script>
    
    
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title><!-- PLACEHOLDER_TITLE --></title>
    <meta name="generator" content="elm-pages v2.1.11" />
    <meta name="mobile-web-app-capable" content="yes" />
    <meta name="theme-color" content="#ffffff" />
    <meta name="apple-mobile-web-app-capable" content="yes" />
    <meta
      name="apple-mobile-web-app-status-bar-style"
      content="black-translucent"
    />
    <!-- PLACEHOLDER_HEAD_AND_DATA -->
    <script type="module" crossorigin src="/assets/index.1764c0d6.js"></script>
    <link rel="stylesheet" href="/assets/index.d0b5e347.css">
  </head>
  <body>
    <div data-url="" display="none"></div>
    <!-- PLACEHOLDER_HTML -->
  </body>
</html>`;

module.exports = {
  async fetch(request) {
    console.log("@@@@ request", request);
    return new Response("Hello!!!!!!");
    // if (new URL(request.url).pathname.startsWith("/assets")) {
    //   return null;
    // }
    const requestTime = new Date();
    global.staticHttpCache = {};

    try {
      global.XMLHttpRequest = {};
      const basePath = "/";
      const mode = "build";
      const addWatcher = () => {};

      const renderResult = await renderer(
        compiledPortsFile,
        basePath,
        Elm,
        mode,
        new URL(request.url).pathname,
        await requestToJson(request, requestTime),
        addWatcher,
        false
      );

      const statusCode = renderResult.is404 ? 404 : renderResult.statusCode;

      if (renderResult.kind === "bytes") {
        return new Response(
          Buffer.from(renderResult.contentDatPayload.buffer),
          {
            headers: {
              "Content-Type": "application/octet-stream",
              "x-powered-by": "elm-pages",
              ...renderResult.headers,
            },
            status: statusCode,
          }
        );
      } else if (renderResult.kind === "api-response") {
        const serverResponse = renderResult.body;
        return new Response(serverResponse.body, {
          // isBase64Encoded: serverResponse.isBase64Encoded, // TODO check if base64 encoded, if it is then convert base64 string to binary
          headers: serverResponse.headers,
          status: serverResponse.statusCode,
        });
      } else {
        return new Response(
          preRenderHtml.replaceTemplate(htmlTemplate, renderResult.htmlString),
          {
            headers: {
              "Content-Type": "text/html",
              "x-powered-by": "elm-pages",
              ...renderResult.headers,
            },
            status: statusCode,
          }
        );
      }
    } catch (error) {
      console.trace(error);
      return new Response(
        `<body><h1>Error</h1><pre>${error.toString()}</pre></body>`,
        {
          status: 500,
          headers: {
            "Content-Type": "text/html",
            "x-powered-by": "elm-pages",
          },
        }
      );
    }
  },
};

async function requestToJson(request, requestTime) {
  return {
    method: request.method,
    body: request.body && (await request.text()),
    headers: request.headers,
    rawUrl: request.url,
    requestTime: Math.round(requestTime.getTime()),
    multiPartFormData: null,
  };
}

/**
 * @param {string[]} parts
 * @returns {string}
 */
function pathJoin(...parts) {
  return parts.join("/");
}
