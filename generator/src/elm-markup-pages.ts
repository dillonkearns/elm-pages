const { Elm } = require("./Main.elm");
const { version } = require("../../package.json");
import * as fs from "fs";
import * as glob from "glob";

function unpackFile(path: string) {
  return { path, contents: fs.readFileSync(path).toString() };
}

const posts = glob.sync("_posts/**/*.emu", {}).map(unpackFile);
const pages = glob.sync("_pages/**/*.emu", {}).map(unpackFile);

// console.log("posts", posts);
// console.log("pages", pages);

let app = Elm.Main.init({
  flags: { argv: process.argv, versionMessage: version, posts, pages }
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
