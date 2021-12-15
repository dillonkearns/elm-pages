const path = require("path");
const fs = require("fs");
const { builder } = require("@netlify/functions");

exports.handler = builder(render);

/**
 * @param {import('aws-lambda').APIGatewayProxyEvent} event
 * @param {any} context
 */
async function render(event, context) {
  fs.mkdirSync(".elm-pages/http-response-cache", { recursive: true });
  console.log(JSON.stringify(event));
  global.staticHttpCache = {};

  const compiledElmPath = path.join(__dirname, "elm-pages-cli.js");
  const renderer = require("../../../../generator/src/render");
  try {
    const basePath = "/";
    /* 
        basePath,
    elmModule,
    mode,
    path,
    request,
    addDataSourceWatcher
    */
    // const renderResult = await renderer(
    //   compiledElmPath,
    //   event.path,
    //   event,
    //   function () {}

    // );
    const mode = "build";
    const addWatcher = () => {};

    const renderResult = await renderer(
      basePath,
      require(compiledElmPath),
      mode,
      event.path,
      event,
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
      body: `<body><h1>Error</h1><pre>${error.toString()}</pre></body>`,
      statusCode: 500,
      headers: {
        "Content-Type": "text/html",
        "x-powered-by": "elm-pages",
      },
    };
  }
}
