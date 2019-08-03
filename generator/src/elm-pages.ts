// @ts-ignore
import { Elm } from "./Main.elm";
import { version } from "../../package.json";
import * as fs from "fs";
import * as glob from "glob";
import * as chokidar from "chokidar";

const contentGlobPath = "content/**/*.emu";

let watcher: chokidar.FSWatcher | null = null;

function unpackFile(path: string) {
  return { path, contents: fs.readFileSync(path).toString() };
}

function run() {
  console.log("Running elm-pages...");
  const content = glob.sync(contentGlobPath, {}).map(unpackFile);
  const markdownContent = glob.sync("content/**/*.md", {}).map(unpackFile);
  const images = glob
    .sync("images/**/*", {})
    .filter(imagePath => !fs.lstatSync(imagePath).isDirectory());

  let app = Elm.Main.init({
    flags: {
      argv: process.argv,
      versionMessage: version,
      content,
      markdownContent,
      images
    }
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
      watch: boolean;
    }) => {
      fs.writeFileSync("./gen/RawContent.elm", contents.rawContent);
      fs.writeFileSync("./prerender.config.js", contents.prerenderrc);
      fs.writeFileSync("./src/js/image-assets.js", contents.imageAssets);
      console.log("elm-pages DONE");
      if (contents.watch) {
        startWatchIfNeeded();
      }
    }
  );
}

run();

function startWatchIfNeeded() {
  if (!watcher) {
    console.log("Watching...");
    watcher = chokidar
      .watch([contentGlobPath, "content/**/*.md"], {
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
  }
}
