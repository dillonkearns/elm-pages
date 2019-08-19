const { compileToString } = require("node-elm-compiler");

module.exports = runElm;
function runElm(callback) {
  const startingDir = process.cwd();
  console.log("cwd", process.cwd());
  process.chdir("./examples/docs/");
  console.log("cwd", process.cwd());
  compileToString(["./src/Main.elm"], {}).then(function(data) {
    eval(data.toString());
    const app = Elm.Main.init({ flags: { imageAssets: {} } });

    app.ports.toJsPort.subscribe(payload => {
      console.log("payload", payload);
      callback(payload);
      process.chdir(startingDir);
      console.log("cwd", process.cwd());
    });
  });
}

runElm(function() {});
