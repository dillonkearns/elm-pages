const path = require("path");

exports.handler = async function (event, context) {
  process.chdir(path.join(__dirname, "../../"));
  const renderer = require("../../../../generator/src/render");
  console.log("pwd", process.cwd());
  return {
    body: (await renderer()).htmlString,
    statusCode: 200,
  };
};
