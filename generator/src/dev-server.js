const express = require("express");
const path = require("path");
const fs = require("fs");
const chokidar = require("chokidar");
const compiledElmPath = path.join(process.cwd(), "elm-stuff/elm-pages/elm.js");
const elmPagesIndexFileContents = require("./index-template.js");
const renderer = require("../../generator/src/render");
const app = express();
const port = 1234;
const { spawnElmMake } = require("./compile-elm.js");

const { inject } = require("elm-hot");

// const pathToTestFixtures = path.join(__dirname, "./fixtures");
// const pathToBuildDir = path.join(pathToTestFixtures, "build");

// try {
//   fs.mkdirSync(pathToBuildDir);
// } catch (error) {
//   if (error.code !== "EEXIST") throw error;
// }
const pathToClientElm = path.join(process.cwd(), "browser-elm.js");
// TODO check source-directories for what to watch?
const watcher = chokidar.watch(
  [path.join(process.cwd(), "src"), path.join(process.cwd(), "content")],

  {
    persistent: true,
  }
);
spawnElmMake("gen/TemplateModulesBeta.elm", pathToClientElm);
spawnElmMake("TemplateModulesBeta.elm", "elm.js", "elm-stuff/elm-pages");

app.get("/stream", function (req, res) {
  res.writeHead(200, {
    Connection: "keep-alive",
    "Content-Type": "text/event-stream",
  });

  watcher.on("change", async function (pathThatChanged, stats) {
    console.log({ pathThatChanged, stats });
    if (pathThatChanged.endsWith(".elm")) {
      await spawnElmMake("gen/TemplateModulesBeta.elm", pathToClientElm);
      console.log("Pushing HMR event to client");
      res.write(`data: /elm.js\n\n`);
    } else {
      console.log("Pushing HMR event to client");
      res.write(`data: content.json\n\n`);
    }
  });
});

app.get("/style.css", (req, res) =>
  res.sendFile(path.join(process.cwd(), "beta-style.css"))
);

app.get("/index.js", (req, res) =>
  res.sendFile(path.join(process.cwd(), "beta-index.js"))
);

app.get("/elm-pages.js", (req, res) => {
  res.set("Content-Type", "text/javascript");
  res.send(elmPagesIndexFileContents);
});

app.get("/elm.js", (req, res) => {
  res.send(inject(fs.readFileSync(pathToClientElm, { encoding: "utf8" })));
  // TODO offer an option to disable hot reloading?
  // res.sendFile(pathToElmCodeJS);
});

app.use(express.static(path.join(process.cwd(), "static")));
app.use("/images", express.static(path.join(process.cwd(), "images")));

app.get("*", async (req, res) => {
  //   const filename = req.params.filename + ".html";
  //   res.sendFile(path.join(process.cwd(), filename));
  //   res.sendFile(path.join(pathToTestFixtures, filename));
  if (req.path.endsWith(".ico") || req.path.endsWith("manifest.json")) {
    res.status(404).end();
  } else {
    try {
      const renderResult = await renderer(compiledElmPath, req.path, req);
      if (renderResult.kind === "json") {
        res.set("Content-Type", "application/json");
        res.end(renderResult.contentJson);
      } else {
        res.set("Content-Type", "text/html");
        res.send(renderResult.htmlString);
      }
    } catch (error) {
      res.set("Content-Type", "text/html");
      res.status(500).send(`<body><h1>Error</h1><pre>${error}</pre></body>`);
    }
  }
});

function startServer(port) {
  return app.listen(port);
}

if (require.main === module) {
  startServer(port);
  console.log(`Server listening at http://localhost:${port}`);
}

module.exports = {
  app,
  startServer: startServer,
};
