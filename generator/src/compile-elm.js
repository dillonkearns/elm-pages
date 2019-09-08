const { compileToString } = require("node-elm-compiler");

module.exports = runElm;
function runElm(callback) {
  const elmBaseDirectory = "./elm-stuff/elm-pages";
  const mainElmFile = "../../src/Main.elm";
  const startingDir = process.cwd();
  process.chdir(elmBaseDirectory);
  compileToString([mainElmFile], {}).then(function(data) {
    (function() {
      const warnOriginal = console.warn;
      console.warn = function() {};
      eval(data.toString());
      const app = Elm.Main.init({ flags: { imageAssets: {} } });

      app.ports.toJsPort.subscribe(payload => {
        if (payload.errors) {
          printErrorsAndExit(payload.errors);
        }

        process.chdir(startingDir);
        callback(payload);
        delete Elm;
        console.warn = warnOriginal;
      });
    })();
  });
}

function printErrorsAndExit(errors) {
  console.error(
    "Found errors. Exiting. Fix your content or parsers and re-run, or run in dev mode with `elm-pages develop`."
  );
  console.error(errors);
  process.exit(1);
}
