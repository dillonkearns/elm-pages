const path = require("path");

exports.handler =
  /**
   * @param {import('aws-lambda').APIGatewayProxyEvent} event
   * @param {any} context
   */
  async function (event, context) {
    console.log(JSON.stringify(event));
    global.staticHttpCache = {};

    const compiledElmPath = path.join(__dirname, "elm-pages-cli.js");
    const { render } = require("../../../../generator/src/render");
    try {
      const renderResult = await render(
        compiledElmPath,
        event.path,
        event,
        function () {}
      );

      if (renderResult.kind === "json") {
        return {
          body: renderResult.contentJson,
          headers: {
            "Content-Type": "application/json",
            "x-powered-by": "elm-pages",
          },
          statusCode: 200,
        };
      } else {
        return {
          body: renderResult.htmlString,
          headers: {
            "Content-Type": "text/html",
            "x-powered-by": "elm-pages",
          },
          statusCode: 200,
        };
      }
    } catch (error) {
      console.error(error);
      return {
        body: `<body><h1>Error</h1><pre>${error}</pre></body>`,
        statusCode: 500,
        headers: {
          "Content-Type": "text/html",
          "x-powered-by": "elm-pages",
        },
      };
    }
  };
