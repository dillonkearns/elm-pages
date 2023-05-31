const renderer = require("../../generator/src/render");
const path = require("path");
const compiledElmPath = path.join(process.cwd(), "elm-stuff/elm-pages/elm.js");
const codegen = require("./codegen.js");
const {
  compileElmForBrowser,
  runElmReview,
  compileCliApp,
} = require("./compile-elm.js");
const { restoreColorSafe } = require("./error-formatter");

async function run({ pathname, serverRequest }) {
  try {
    const basePath = "/";
    await codegen.generate(basePath);
    console.log("Compiling...");
    await compileCliApp(
      { port: 1234, base: basePath, https: false, debug: true },
      ".elm-pages/Main.elm",

      path.join(process.cwd(), "elm-stuff/elm-pages/", "elm.js"),

      // "elm.js",
      "elm-stuff/elm-pages/",
      path.join("elm-stuff/elm-pages/", "elm.js")
    );
    console.log("Compiling DONE");

    const portsFilePath =
      ".elm-pages/compiled-ports/custom-backend-task-FA2IJND6.js";
    const mode = "dev-server";

    const renderResult = await renderer.render(
      portsFilePath,
      basePath,
      require(compiledElmPath),
      mode,
      pathname,
      serverRequest,
      function (patterns) {},
      true
    );
    console.log("renderResult", renderResult);
  } catch (error) {
    console.log("ERROR");
    console.log(restoreColorSafe(error));
  }
}

// run({
//   serverRequest: {
//     method: "POST",
//     headers: {
//       host: "localhost:1234",
//       cookie: "darkMode=%7B%7D.X1hjuYBa1OZulUomD5yrPy6VcYeY3sC7SKZVGViT0Q4",
//       accept: "*/*",
//       "accept-language": "en-US,en;q=0.9",
//       connection: "keep-alive",
//       "content-type": "application/x-www-form-urlencoded",
//       origin: "http://localhost:1234",
//       referer: "http://localhost:1234/dark-mode",
//     },
//     rawUrl: "http://localhost:1234/dark-mode/content.dat",
//     body: "name=1",
//     requestTime: 1671391652138,
//     multiPartFormData: null,
//   },
//   pathname: "/dark-mode/content.dat",
// });

// run({
//   pathname: "/fetcher/content.dat",
//   serverRequest: {
//     method: "POST",
//     headers: {
//       host: "localhost:1234",
//       cookie: "darkMode=%7B%7D",
//       accept: "*/*",
//       "content-type": "application/x-www-form-urlencoded",
//       origin: "http://localhost:1234",
//       referer: "http://localhost:1234/fetcher",
//     },
//     rawUrl: "http://localhost:1234/fetcher/content.dat",
//     body: "name=1",
//     requestTime: 1671296755228,
//     multiPartFormData: null,
//   },
// });

run({
  serverRequest: {
    method: "POST",
    headers: {
      host: "localhost:1234",
      "cache-control": "max-age=0",
      accept:
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
      "content-type": "application/x-www-form-urlencoded",
      referer: "http://localhost:1234/login",
      cookie:
        "darkMode=%7B%22darkMode%22%3A%22%22%7D.vtrl8xZXjtx9E3iidJrgurAz4Vk7rnMQmf6zKiAbwNo; mysession=%7B%7D.YX1rW5PIpRFkjgIjLn4p9iyl5r9kWLYHqQUYxAYKJgQ",
    },
    rawUrl: "http://localhost:1234/login/content.dat",
    body: "name=1",
    requestTime: 1671391652138,
    multiPartFormData: null,
  },
  pathname: "/login/content.dat",
});
