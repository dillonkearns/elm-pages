// @ts-ignore
import { Elm } from "./Main.elm";
import { version } from "../../package.json";
import * as fs from "fs";
import * as glob from "glob";
import * as chokidar from "chokidar";

function unpackFile(path: string) {
  return { path, contents: fs.readFileSync(path).toString() };
}

function run() {
  const content = glob.sync("content/**/*.emu", {}).map(unpackFile);
  const images = glob
    .sync("images/**/*", {})
    .filter(imagePath => !fs.lstatSync(imagePath).isDirectory());

  let app = Elm.Main.init({
    flags: { argv: process.argv, versionMessage: version, content, images }
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
      fs.writeFileSync("./prerender.config.js", contents.prerenderrc);
      fs.writeFileSync("./src/js/image-assets.js", contents.imageAssets);
    }
  );
}

run();

chokidar
  .watch(["./_pages/**/*.emu", "./_posts/**/*.emu"], {
    awaitWriteFinish: {
      stabilityThreshold: 500
    },
    ignoreInitial: true
  })
  .on("all", function(event, filePath) {
    console.log(`Rerunning for ${filePath}...`);
    run();
    console.log("Done!");
  });
