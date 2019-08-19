const { Elm } = require("./cli.js");

const app = Elm.Main.init();

app.ports.toCli.subscribe(payload => {
  console.log("payload", payload);
});
