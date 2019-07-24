// @ts-ignore
import { Elm } from "./Main.elm";
import { version } from "../../package.json";
import * as fs from "fs";
import * as glob from "glob";

function unpackFile(path: string) {
  return { path, contents: fs.readFileSync(path).toString() };
}

const posts = glob.sync("_posts/**/*.emu", {}).map(unpackFile);
const pages = glob.sync("_pages/**/*.emu", {}).map(unpackFile);
const images = glob.sync("images/**/*", {});

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

app.ports.writeFile.subscribe(
  (contents: {
    rawContent: string;
    prerenderrc: string;
    imageAssets: string;
  }) => {
    fs.writeFileSync("./gen/RawContent.elm", contents.rawContent);
    fs.writeFileSync("./.prerenderrc", contents.prerenderrc);
    console.log("image assets", contents.imageAssets);
    fs.writeFileSync("./src/js/image-assets.js", contents.imageAssets);
  }
);
