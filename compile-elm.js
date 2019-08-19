var compile = require("node-elm-compiler").compile;
var compileToString = require("node-elm-compiler").compileToString;

process.chdir("./examples/docs/");
compileToString(["./src/Main.elm"], {}).then(function(data) {
  eval(data.toString());
  const app = Elm.Main.init({ flags: { imageAssets: {} } });

  app.ports.toJsPort.subscribe(payload => {
    console.log("payload", payload);
  });
});
