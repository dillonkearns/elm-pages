const fs = require("fs");

async function run({ renderFunctionFilePath, routePatterns }) {
  fs.mkdirSync("functions/render");
  fs.mkdirSync("functions/server-render");
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

  console.log(routePatterns);
  const redirectsFile =
    routePatterns
      .filter(isServerSide)
      .map((route) => {
        if (route.kind === "prerender-with-fallback") {
          return `${route.pathPattern} /.netlify/functions/render 200
${route.pathPattern}/content.json /.netlify/functions/render 200`;
        } else {
          return `${route.pathPattern} /.netlify/functions/server-render 200
${route.pathPattern}/content.json /.netlify/functions/server-render 200`;
        }
      })
      .join("\n") + "\n";

  fs.writeFileSync("dist/_redirects", redirectsFile);
}

function isServerSide(route) {
  return (
    route.kind === "prerender-with-fallback" || route.kind === "serverless"
  );
}

run({
  renderFunctionFilePath: "./elm-stuff/elm-pages/elm.js",
  routePatterns: JSON.parse(fs.readFileSync("dist/route-patterns.json")),
});

/**
 * @param {boolean} isOnDemand
 */
function rendererCode(isOnDemand) {
  return `const path = require("path");
${
  isOnDemand
    ? `const { builder } = require("@netlify/functions");

exports.handler = builder(render);`
    : `

exports.handler = render;`
}


const path = require("path");
const fs = require("fs");
const { builder } = require("@netlify/functions");

exports.handler = builder(render);

/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} event
 * @param {any} context
 */
async function render(event, context) {
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
      reqToJson(event),
      addWatcher
    );

    const statusCode = renderResult.is404 ? 404 : 200;

    if (renderResult.kind === "json") {
      return {
        body: renderResult.contentJson,
        headers: {
          "Content-Type": "application/json",
          "x-powered-by": "elm-pages",
        },
        statusCode,
      };
    } else {
      return {
        body: renderResult.htmlString,
        headers: {
          "Content-Type": "text/html",
          "x-powered-by": "elm-pages",
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

//  * @param {import('aws-lambda').APIGatewayProxyEvent} event

/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} req
 * @returns {{ method: string; hostname: string; query: string; headers: Object; host: string; pathname: string; port: number | null; protocol: string; rawUrl: string; }}
 */
function reqToJson(req) {
  return {
    method: req.httpMethod,
    hostname: "TODO",
    // query: req.queryStringParameters, //url.search ? url.search.substring(1) : "",
    query: "", //url.search ? url.search.substring(1) : "",
    headers: req.headers,
    host: "", // TODO
    pathname: req.path,
    port: 80, // TODO
    protocol: "https", // TODO
    rawUrl: "", // TODO
  };
}
`;
}
