/**
 * Welcome to Cloudflare Workers! This is your first worker.
 *
 * - Run `wrangler dev src/index.ts` in your terminal to start a development server
 * - Open a browser tab at http://localhost:8787/ to see your worker in action
 * - Run `wrangler publish src/index.ts --name my-worker` to publish your worker
 *
 * Learn more at https://developers.cloudflare.com/workers/
 */

// const path = require("path");
// const compiledElmPath = path.join(__dirname, "elm-pages-cli.js");
// const compiledPortsFile = path.join(__dirname, "port-data-source.mjs");
// const renderer = require("elm-pages/generator/src/render.js");
// const preRenderHtml = require("elm-pages/generator/src/pre-render-html.js");

export default {
  async fetch(request: Request): Promise<Response> {
    return new Response("hello!");
    const requestTime = new Date();
    global.staticHttpCache = {};

    try {
      const basePath = "/";
      const mode = "build";
      const addWatcher = () => {};

      const renderResult = await renderer(
        compiledPortsFile,
        basePath,
        require(compiledElmPath),
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
      console.error(error);
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

async function requestToJson(request: Request, requestTime) {
  return {
    method: request.method,
    body: request.body && (await request.text()),
    headers: request.headers,
    rawUrl: request.url,
    requestTime: Math.round(requestTime.getTime()),
    multiPartFormData: null,
  };
}
