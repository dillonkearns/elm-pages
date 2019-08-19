const { compileToString } = require("node-elm-compiler");

module.exports = runElm;
function runElm(callback) {
  const elmBaseDirectory = "./elm-stuff/elm-pages";
  const mainElmFile = "../../src/Main.elm";
  const startingDir = process.cwd();
  process.chdir(elmBaseDirectory);
  compileToString([mainElmFile], {}).then(function(data) {
    eval(data.toString());
    const app = Elm.Main.init({ flags: { imageAssets: {} } });

    app.ports.toJsPort.subscribe(payload => {
      callback(payload);
      process.chdir(startingDir);
    });
  });
}
