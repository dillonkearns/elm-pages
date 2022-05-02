import fs from "fs";

export default async function run({
  renderFunctionFilePath,
  routePatterns,
  apiRoutePatterns,
  portsFilePath,
  htmlTemplate,
}) {
  ensureDirSync("functions/");

  // TODO figure out where to put the cli.js file and port-data-source file
  ensureDirSync("../../functions");
  fs.copyFileSync(renderFunctionFilePath, "./dist/elm-pages-cli.js");
  // fs.copyFileSync(
  //   portsFilePath,
  //   "./functions/server-render/port-data-source.mjs"
  // );
  fs.writeFileSync("../../functions/[[path]].js", rendererCode(htmlTemplate));
}

/**
 * @param {string} htmlTemplate
 */
function rendererCode(htmlTemplate) {
  return `const htmlTemplate = ${JSON.stringify(htmlTemplate)};
const devMode = true;

const compiledPortsFile = "../dist/port-data-source.mjs";
const Elm = require("./examples/hackernews-cloudflare/dist/elm-pages-cli.js");
const renderer = require("../generator/src/render.js");
const preRenderHtml = require("../generator/src/pre-render-html.js");


export async function onRequest(context) {
  const { request, env, next } = context;

  let res = await next();
  if (res.status !== 404) {
    return res;
  }

  try {
    const requestTime = new Date();
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
      false,
      {
        getEnv: function (name) {
          return env[name];
        },
      }
    );

    const statusCode = renderResult.is404 ? 404 : renderResult.statusCode;

    if (renderResult.kind === "bytes") {
      return new Response(renderResult.contentDatPayload.buffer, {
        headers: {
          "Content-Type": "application/octet-stream",
          "x-powered-by": "elm-pages",
          ...renderResult.headers,
        },
        status: statusCode,
      });
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
    if (devMode) {
      return new Response(
        \`<body><h1>Error</h1><pre>\${error.toString()}</pre><div><pre>\${
          error.stack
        }</pre></div></body>\`,
        {
          status: 500,
          headers: {
            "Content-Type": "text/html",
            "x-powered-by": "elm-pages",
          },
        }
      );
    } else {
      return new Response(\`<body><h1>Internal Error</h1></body>\`, {
        status: 500,
        headers: {
          "Content-Type": "text/html",
          "x-powered-by": "elm-pages",
        },
      });
    }
  }
}
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
`;
}

/**
 * @param {fs.PathLike} dirpath
 */
function ensureDirSync(dirpath) {
  try {
    fs.mkdirSync(dirpath, { recursive: true });
  } catch (err) {
    if (err.code !== "EEXIST") throw err;
  }
}
