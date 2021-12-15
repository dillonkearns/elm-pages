const fs = require("fs");

async function run({ renderFunctionFilePath, routePatterns }) {
  fs.copyFileSync(
    renderFunctionFilePath,
    "./functions/render/elm-pages-cli.js"
  );
  // TODO also copy renderFunctionFilePath to server-render function folder?
  // TODO copy DPR render serverless function to functions folder
  // TODO copy server-request render serverless function to functions folder
  // TODO rename functions/render to functions/fallback-render

  // TODO prepend instead of writing file
  console.log(routePatterns);
  const redirectsFile =
    routePatterns
      .filter(isServerSide)
      .map((route) => {
        if (route.pathPattern === "prerender-with-fallback") {
          return `${route.pathPattern} /.netlify/functions/render 200`;
        } else {
          return `${route.pathPattern} /.netlify/functions/server-render 200`;
        }
      })
      .join("\n") + "\n";

  fs.writeFileSync("dist/_redirects", redirectsFile);
}

function isServerSide(route) {
  return (
    route.kind === "prerender-with-fallback" || route.kind === "serverless"
  );
}

run({
  renderFunctionFilePath: "./elm-stuff/elm-pages/elm.js",
  routePatterns: JSON.parse(fs.readFileSync("dist/route-patterns.json")),
});
