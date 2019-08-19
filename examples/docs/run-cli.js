const { Elm } = require("./cli.js");

const app = Elm.Main.init();

app.ports.toJsPort.subscribe(payload => {
  console.log("payload", payload);
});
