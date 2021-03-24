const path = require("path");

exports.handler = async function (event, context) {
  console.log(JSON.stringify(event));
  // process.chdir(path.join(__dirname, "../../"));
  // process.chdir("../");

  // const compiledElmPath = path.join(process.cwd(), "elm-pages-cli.js");
  const compiledElmPath = path.join(__dirname, "elm-pages-cli.js");
  const renderer = require("../../../../generator/src/render");
  console.log("pwd", process.cwd());
  return {
    body: (await renderer(compiledElmPath)).htmlString,
    statusCode: 200,
  };
};
