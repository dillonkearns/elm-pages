// const path = require("path");

exports.handler = async function (event, context) {
  console.log(JSON.stringify(event));
  // process.chdir(path.join(__dirname, "../../"));
  process.chdir("../");
  const renderer = require("../../../../generator/src/render");
  console.log("pwd", process.cwd());
  return {
    body: (await renderer()).htmlString,
    statusCode: 200,
  };
};
