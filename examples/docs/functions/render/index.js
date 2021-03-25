const path = require("path");

exports.handler =
  /**
   * @param {import('aws-lambda').APIGatewayProxyEvent} event
   * @param {any} context
   */
  async function (event, context) {
    // event.path
    console.log(JSON.stringify(event));
    // process.chdir(path.join(__dirname, "../../"));
    // process.chdir("../");

    // const compiledElmPath = path.join(process.cwd(), "elm-pages-cli.js");
    const compiledElmPath = path.join(__dirname, "elm-pages-cli.js");
    const renderer = require("../../../../generator/src/render");
    // console.log("pwd", process.cwd());
    return {
      body: (await renderer(compiledElmPath, event.path, event)).htmlString,
      statusCode: 200,
    };
  };
