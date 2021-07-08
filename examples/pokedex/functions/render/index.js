const path = require("path");
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
    const renderResult = await renderer(
      compiledElmPath,
      event.path,
      event,
      function () {}
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
