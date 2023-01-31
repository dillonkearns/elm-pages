import * as fs from "fs";
import * as path from "path";

export default async function run({
  renderFunctionFilePath,
  routePatterns,
  apiRoutePatterns,
  portsFilePath,
  htmlTemplate,
}) {
  console.log("Running adapter script");
  ensureDirSync("functions/render");
  ensureDirSync("functions/server-render");

  fs.copyFileSync(
    renderFunctionFilePath,
    "./functions/render/elm-pages-cli.cjs"
  );
  fs.copyFileSync(
    renderFunctionFilePath,
    "./functions/server-render/elm-pages-cli.cjs"
  );

  fs.writeFileSync(
    "./functions/render/index.mjs",
    rendererCode(true, htmlTemplate)
  );
  fs.writeFileSync(
    "./functions/server-render/index.mjs",
    rendererCode(false, htmlTemplate)
  );
  // TODO rename functions/render to functions/fallback-render
  // TODO prepend instead of writing file

  const apiServerRoutes = apiRoutePatterns.filter(isServerSide);

  ensureValidRoutePatternsForNetlify(apiServerRoutes);

  // TODO filter apiRoutePatterns on is server side
  // TODO need information on whether api route is odb or serverless
  const apiRouteRedirects = apiServerRoutes
    .map((apiRoute) => {
      if (apiRoute.kind === "prerender-with-fallback") {
        return `${apiPatternToRedirectPattern(
          apiRoute.pathPattern
        )} /.netlify/builders/render 200`;
      } else if (apiRoute.kind === "serverless") {
        return `${apiPatternToRedirectPattern(
          apiRoute.pathPattern
        )} /.netlify/functions/server-render 200`;
      } else {
        throw "Unhandled 2";
      }
    })
    .join("\n");

  const redirectsFile =
    routePatterns
      .filter(isServerSide)
      .map((route) => {
        if (route.kind === "prerender-with-fallback") {
          return `${route.pathPattern} /.netlify/builders/render 200
${route.pathPattern}/content.dat /.netlify/builders/render 200`;
        } else {
          return `${route.pathPattern} /.netlify/functions/server-render 200
${route.pathPattern}/content.dat /.netlify/functions/server-render 200`;
        }
      })
      .join("\n") +
    "\n" +
    apiRouteRedirects +
    "\n";

  fs.writeFileSync("dist/_redirects", redirectsFile);
}

function ensureValidRoutePatternsForNetlify(apiRoutePatterns) {
  const invalidNetlifyRoutes = apiRoutePatterns.filter((apiRoute) =>
    apiRoute.pathPattern.some(({ kind }) => kind === "hybrid")
  );
  if (invalidNetlifyRoutes.length > 0) {
    throw (
      "Invalid Netlify routes!\n" +
      invalidNetlifyRoutes
        .map((value) => JSON.stringify(value, null, 2))
        .join(", ")
    );
  }
}

function isServerSide(route) {
  return (
    route.kind === "prerender-with-fallback" || route.kind === "serverless"
  );
}

/**
 * @param {boolean} isOnDemand
 * @param {string} htmlTemplate
 */
function rendererCode(isOnDemand, htmlTemplate) {
  return `import * as path from "path";
import * as busboy from "busboy";
import { fileURLToPath } from "url";
import * as renderer from "../../../../generator/src/render.js";
import * as preRenderHtml from "../../../../generator/src/pre-render-html.js";
import * as customBackendTask from "${path.resolve(portsFilePath)}";
const htmlTemplate = ${JSON.stringify(htmlTemplate)};

${
  isOnDemand
    ? `import { builder } from "@netlify/functions";

export const handler = builder(render);`
    : `

export const handler = render;`
}


/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} event
 * @param {any} context
 */
async function render(event, context) {
  const requestTime = new Date();
  console.log(JSON.stringify(event));

  try {
    const basePath = "/";
    const mode = "build";
    const addWatcher = () => {};

    const renderResult = await renderer.render(
      customBackendTask,
      basePath,
      (await import("./elm-pages-cli.cjs")).default,
      mode,
      event.path,
      await reqToJson(event, requestTime),
      addWatcher,
      false
    );
    console.log("@@@renderResult", JSON.stringify(renderResult, null, 2));

    const statusCode = renderResult.is404 ? 404 : renderResult.statusCode;

    if (renderResult.kind === "bytes") {
      return {
        body: Buffer.from(renderResult.contentDatPayload.buffer).toString("base64"),
        isBase64Encoded: true,
        headers: {
          "Content-Type": "application/octet-stream",
          "x-powered-by": "elm-pages",
          ...renderResult.headers,
        },
        statusCode,
      };
    } else if (renderResult.kind === "api-response") {
      const serverResponse = renderResult.body;
      return {
        body: serverResponse.body,
        multiValueHeaders: serverResponse.headers,
        statusCode: serverResponse.statusCode,
        isBase64Encoded: serverResponse.isBase64Encoded,
      };
    } else {
      console.log('@rendering', preRenderHtml.replaceTemplate(htmlTemplate, renderResult.htmlString))
      return {
        body: preRenderHtml.replaceTemplate(htmlTemplate, renderResult.htmlString),
        headers: {
          "Content-Type": "text/html",
          "x-powered-by": "elm-pages",
          ...renderResult.headers,
        },
        statusCode,
      };
    }
  } catch (error) {
    console.log('ERROR')
    console.error(error);
    console.error(JSON.stringify(error, null, 2));
    return {
      body: \`<body><h1>Error</h1><pre>\${error.toString()}</pre></body>\`,
      statusCode: 500,
      headers: {
        "Content-Type": "text/html",
        "x-powered-by": "elm-pages",
      },
    };
  }
}

/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} req
 * @param {Date} requestTime
 * @returns {Promise<{ method: string; hostname: string; query: Record<string, string | undefined>; headers: Record<string, string>; host: string; pathname: string; port: number | null; protocol: string; rawUrl: string; }>}
 */
function reqToJson(req, requestTime) {
  return new Promise((resolve, reject) => {
    if (
      req.httpMethod && req.httpMethod.toUpperCase() === "POST" &&
      req.headers["content-type"] &&
      req.headers["content-type"].includes("multipart/form-data") &&
      req.body
    ) {
      try {
        console.log('@@@1');
        const bb = busboy({
          headers: req.headers,
        });
        let fields = {};

        bb.on("file", (fieldname, file, info) => {
          console.log('@@@2');
          const { filename, encoding, mimeType } = info;

          file.on("data", (data) => {
            fields[fieldname] = {
              filename,
              mimeType,
              body: data.toString(),
            };
          });
        });

        bb.on("field", (fieldName, value) => {
          console.log("@@@field", fieldName, value);
          fields[fieldName] = value;
        });

        // TODO skip parsing JSON and form data body if busboy doesn't run
        bb.on("close", () => {
          console.log('@@@3');
          console.log("@@@close", fields);
          resolve(toJsonHelper(req, requestTime, fields));
        });
        console.log('@@@4');
        
        if (req.isBase64Encoded) {
          bb.write(Buffer.from(req.body, 'base64').toString('utf8'));
        } else {
          bb.write(req.body);
        }
      } catch (error) {
        console.error('@@@5', error);
        resolve(toJsonHelper(req, requestTime, null));
      }
    } else {
      console.log('@@@6');
      resolve(toJsonHelper(req, requestTime, null));
    }
  });
}

/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} req
 * @param {Date} requestTime
 * @returns {{method: string; rawUrl: string; body: string?; headers: Record<string, string>; requestTime: number; multiPartFormData: unknown }}
 */
function toJsonHelper(req, requestTime, multiPartFormData) {
  return {
    method: req.httpMethod,
    headers: req.headers,
    rawUrl: req.rawUrl,
    body: req.body,
    requestTime: Math.round(requestTime.getTime()),
    multiPartFormData: multiPartFormData,
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

/** @typedef {{kind: 'dynamic'} | {kind: 'literal', value: string}} ApiSegment */

/**
 * @param {ApiSegment[]} pathPattern
 */
function apiPatternToRedirectPattern(pathPattern) {
  return (
    "/" +
    pathPattern
      .map((segment, index) => {
        switch (segment.kind) {
          case "literal": {
            return segment.value;
          }
          case "dynamic": {
            return `:dynamic${index}`;
          }
          default: {
            throw "Unhandled segment: " + JSON.stringify(segment);
          }
        }
      })
      .join("/")
  );
}
