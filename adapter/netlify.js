import * as fs from "fs";

export default async function run({
  renderFunctionFilePath,
  routePatterns,
  apiRoutePatterns,
}) {
  console.log("Running Netlify adapter");
  ensureDirSync("functions/render");
  ensureDirSync("functions/server-render");

  fs.copyFileSync(
    renderFunctionFilePath,
    "./functions/render/elm-pages-cli.mjs"
  );
  fs.copyFileSync(
    renderFunctionFilePath,
    "./functions/server-render/elm-pages-cli.mjs"
  );

  fs.writeFileSync("./functions/render/index.mjs", rendererCode(true));
  fs.writeFileSync("./functions/server-render/index.mjs", rendererCode(false));
  // TODO rename functions/render to functions/fallback-render
  // TODO prepend instead of writing file

  const apiServerRoutes = apiRoutePatterns.filter(isServerSide);

  ensureValidRoutePatternsForNetlify(apiServerRoutes);

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
        throw "Unhandled API Server Route";
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
 */
function rendererCode(isOnDemand) {
  return `import * as elmPages from "./elm-pages-cli.mjs";
import * as busboy from "busboy";

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
  try {
    const renderResult = await elmPages.render(await reqToJson(event));
    const { headers, statusCode } = renderResult;

    if (renderResult.kind === "bytes") {
      return {
        body: Buffer.from(renderResult.body).toString("base64"),
        isBase64Encoded: true,
        multiValueHeaders: {
          "Content-Type": ["application/octet-stream"],
          "x-powered-by": ["elm-pages"],
          ...headers,
        },
        statusCode,
      };
    } else if (renderResult.kind === "api-response") {
      return {
        body: renderResult.body,
        multiValueHeaders: headers,
        statusCode,
        isBase64Encoded: renderResult.isBase64Encoded,
      };
    } else {
      return {
        body: renderResult.body,
        multiValueHeaders: {
          "Content-Type": ["text/html"],
          "x-powered-by": ["elm-pages"],
          ...headers,
        },
        statusCode,
      };
    }
  } catch (error) {
    console.error(error);
    console.error(JSON.stringify(error, null, 2));
    return {
      body: \`<body><h1>Error</h1><pre>\${JSON.stringify(error, null, 2)}</pre></body>\`,
      statusCode: 500,
      multiValueHeaders: {
        "Content-Type": ["text/html"],
        "x-powered-by": ["elm-pages"],
      },
    };
  }
}

/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} req
 * @returns {{method: string; rawUrl: string; body: string?; headers: Record<string, string>; multiPartFormData: unknown }}
 */
function reqToJson(req) {
  return {
    method: req.httpMethod,
    headers: req.headers,
    rawUrl: req.rawUrl,
    body: req.body,
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
