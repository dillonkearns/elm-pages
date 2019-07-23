const { Elm } = require("./Main.elm");
const { version } = require("../../package.json");

let app = Elm.Main.init({
  flags: { argv: process.argv, versionMessage: version }
});

app.ports.printAndExitSuccess.subscribe((message: string) => {
  console.log(message);
  process.exit(0);
});

app.ports.printAndExitFailure.subscribe((message: string) => {
  console.log(message);
  process.exit(1);
});

app.ports.print.subscribe((message: string) => {
  console.log(message);
});
