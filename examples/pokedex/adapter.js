const fs = require("fs");

async function run({
  renderFunctionFilePath,
  routePatterns,
  apiRoutePatterns,
}) {
  ensureDirSync("functions/render");
  ensureDirSync("functions/server-render");

  fs.copyFileSync(
    renderFunctionFilePath,
    "./functions/render/elm-pages-cli.js"
  );
  fs.copyFileSync(
    renderFunctionFilePath,
    "./functions/server-render/elm-pages-cli.js"
  );
  fs.writeFileSync("./functions/render/index.js", rendererCode(true));
  fs.writeFileSync("./functions/server-render/index.js", rendererCode(false));
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

(async function () {
  try {
    await run({
      renderFunctionFilePath: "./elm-stuff/elm-pages/elm.js",
      routePatterns: JSON.parse(fs.readFileSync("dist/route-patterns.json")),
      apiRoutePatterns: JSON.parse(fs.readFileSync("dist/api-patterns.json")),
    });
    console.log("Success - Adapter script complete");
  } catch (error) {
    console.error("ERROR - Adapter script failed");
    console.error(error);
    process.exit(1);
  }
})();

/**
 * @param {boolean} isOnDemand
 */
function rendererCode(isOnDemand) {
  return `const path = require("path");
const cookie = require("cookie");
const busboy = require("busboy");

${
  isOnDemand
    ? `const { builder } = require("@netlify/functions");

exports.handler = builder(render);`
    : `

exports.handler = render;`
}


/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} event
 * @param {any} context
 */
async function render(event, context) {
  const requestTime = new Date();
  console.log(JSON.stringify(event));
  global.staticHttpCache = {};

  const compiledElmPath = path.join(__dirname, "elm-pages-cli.js");
  const renderer = require("../../../../generator/src/render");
  try {
    const basePath = "/";
    const mode = "build";
    const addWatcher = () => {};

    const renderResult = await renderer(
      basePath,
      require(compiledElmPath),
      mode,
      event.path,
      await reqToJson(event, requestTime),
      addWatcher,
      false
    );
    console.log("@@@renderResult", JSON.stringify(renderResult, null, 2));

    const statusCode = renderResult.is404 ? 404 : renderResult.statusCode;

    if (renderResult.kind === "json") {
      return {
        body: renderResult.contentJson,
        headers: {
          "Content-Type": "application/json",
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
      return {
        body: renderResult.htmlString,
        headers: {
          "Content-Type": "text/html",
          "x-powered-by": "elm-pages",
          ...renderResult.headers,
        },
        statusCode,
      };
    }
  } catch (error) {
    console.error(error);
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

function toJsonHelper(req, requestTime, multiPartFormData) {
  let jsonBody = null;
  try {
    jsonBody = req.body && JSON.parse(req.body);
  } catch (jsonParseError) {}
  return {
    method: req.httpMethod,
    hostname: "TODO",
    query: req.queryStringParameters || {},
    headers: req.headers,
    host: "", // TODO
    pathname: req.path,
    port: 80, // TODO
    protocol: "https", // TODO
    rawUrl: "", // TODO
    body: req.body,
    requestTime: Math.round(requestTime.getTime()),
    cookies: cookie.parse(req.headers.cookie || ""),
    // TODO skip parsing if content-type is not x-www-form-urlencoded
    formData: paramsToObject(new URLSearchParams(req.body || "")),
    multiPartFormData: multiPartFormData,
    jsonBody: jsonBody,
  };
}

function paramsToObject(entries) {
  const result = {};
  for (const [key, value] of entries) {
    result[key] = value || "";
  }
  return result;
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
            return `:dynamic${index}`; // TODO need to assign different names for each dynamic segment?
          }
          default: {
            throw "Unhandled segment: " + JSON.stringify(segment);
          }
        }
      })
      .join("/")
  );
}
