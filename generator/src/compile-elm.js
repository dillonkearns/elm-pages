const { compileToString } = require("../node-elm-compiler/index.js");
XMLHttpRequest = require("xhr2");

module.exports = runElm;
function runElm(/** @type string */ mode) {
  return new Promise((resolve, reject) => {
    const elmBaseDirectory = "./elm-stuff/elm-pages";
    const mainElmFile = "../../src/Main.elm";
    const startingDir = process.cwd();
    process.chdir(elmBaseDirectory);
    compileToString([mainElmFile], {}).then(function (data) {
      (function () {
        const warnOriginal = console.warn;
        console.warn = function () { };
        eval(data.toString());
        const app = Elm.Main.init({
          flags: { secrets: process.env, mode, staticHttpCache: global.staticHttpCache }
        });

        app.ports.toJsPort.subscribe(payload => {
          process.chdir(startingDir);

          if (payload.tag === "Success") {
            global.staticHttpCache = payload.args[0].staticHttpCache;
            resolve(payload.args[0])
          } else {
            reject(payload.args[0])
          }
          delete Elm;
          console.warn = warnOriginal;
        });
      })();

    })
  });
}
