const path = require("path");

exports.handler =
  /**
   * @param {import('aws-lambda').APIGatewayProxyEvent} event
   * @param {any} context
   */
  async function (event, context) {
    console.log(JSON.stringify(event));

    const compiledElmPath = path.join(__dirname, "elm-pages-cli.js");
    const renderer = require("../../../../generator/src/render");
    try {
      const renderResult = await renderer(compiledElmPath, event.path, event);

      return {
        body: renderResult.htmlString,
        statusCode: 200,
      };
    } catch (error) {
      return {
        // body: JSON.stringify({ error }),
        body: `<body><h1>Error</h1><pre>${error}</pre></body>`,
        statusCode: 500,
        headers: [{ "content-type": "text/html" }],
      };
    }
  };
