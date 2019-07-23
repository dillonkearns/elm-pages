const { Elm } = require("./Main.elm");
const { version } = require("../../package.json");
import * as glob from "glob";

console.log("glob", glob.sync("_posts/**/*.emu", {}));
console.log("glob", glob.sync("_pages/**/*.emu", {}));

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
