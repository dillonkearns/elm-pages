const express = require("express");
const path = require("path");
const fs = require("fs");
const chokidar = require("chokidar");
const compiledElmPath = path.join(process.cwd(), "elm-stuff/elm-pages/elm.js");
const renderer = require("../../generator/src/render");
const app = express();
const port = 1234;

// const { inject } = require("../src/inject.js");

// const pathToTestFixtures = path.join(__dirname, "./fixtures");
// const pathToBuildDir = path.join(pathToTestFixtures, "build");

// try {
//   fs.mkdirSync(pathToBuildDir);
// } catch (error) {
//   if (error.code !== "EEXIST") throw error;
// }
// const watcher = chokidar.watch(pathToBuildDir, { persistent: true });

app.get("/client.js", (req, res) =>
  res.sendFile(path.join(__dirname, "./client.js"))
);

app.get("/style.css", (req, res) =>
  res.sendFile(path.join(process.cwd(), "beta-style.css"))
);

app.get("/index.js", (req, res) =>
  res.sendFile(path.join(process.cwd(), "beta-index.js"))
);

app.get("/elm-pages.js", (req, res) =>
  res.sendFile(path.join(process.cwd(), "dist/elm-pages.js"))
);
app.get("/elm.js", (req, res) =>
  res.sendFile(path.join(process.cwd(), "dist/elm.js"))
);

app.use(express.static(path.join(process.cwd(), "static")));
app.use("/images", express.static(path.join(process.cwd(), "images")));

app.get("*", async (req, res) => {
  //   const filename = req.params.filename + ".html";
  //   res.sendFile(path.join(process.cwd(), filename));
  //   res.sendFile(path.join(pathToTestFixtures, filename));
  try {
    // const renderResult = await renderer(compiledElmPath, req.path, event);
    const renderResult = await renderer(compiledElmPath, req.path, req);

    if (renderResult.kind === "json") {
      res.set("Content-Type", "application/json");
      res.send(renderResult.contentJson);
    } else {
      res.set("Content-Type", "text/html");
      res.send(renderResult.htmlString);
    }
  } catch (error) {
    res.set("Content-Type", "text/html");
    res.status(500).send(`<body><h1>Error</h1><pre>${error}</pre></body>`);
  }
});

// app.get("/build/:filename.js", function (req, res) {
//   const filename = req.params.filename + ".js";
//   const pathToElmCodeJS = path.join(pathToBuildDir, filename);
//   const originalElmCodeJS = fs.readFileSync(pathToElmCodeJS, {
//     encoding: "utf8",
//   });
//   const fullyInjectedCode = inject(originalElmCodeJS);
//   res.send(fullyInjectedCode);
// });

app.get("/stream-:programName", function (req, res) {
  const programName = req.params.programName;
  res.writeHead(200, {
    Connection: "keep-alive",
    "Content-Type": "text/event-stream",
  });

  //   watcher.on("change", function (pathThatChanged, stats) {
  //     if (pathThatChanged.endsWith(programName + ".js")) {
  //       //console.log("Pushing HMR event to client");
  //       const relativeLoadPath = path.relative(
  //         pathToTestFixtures,
  //         pathThatChanged
  //       );
  //       res.write(`data: ${relativeLoadPath}\n\n`);
  //     }
  //   });
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
