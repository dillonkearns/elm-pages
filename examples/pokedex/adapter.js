const fs = require("fs");

async function run({ renderFunctionFilePath, serverRoutes, fallbackRoutes }) {
  fs.copyFileSync(
    renderFunctionFilePath,
    "./functions/render/elm-pages-cli.js"
  );
  // TODO also copy renderFunctionFilePath to server-render function folder?
  // TODO copy DPR render serverless function to functions folder
  // TODO copy server-request render serverless function to functions folder
  // TODO rename functions/render to functions/fallback-render

  // TODO prepend instead of writing file
  fs.writeFileSync(
    "dist/_redirects",
    `${fallbackRoutes.map(
      (route) => `${toRoute(route)} /.netlify/functions/render 200\n`
    )}

${serverRoutes.map(
  (route) => `${toRoute(route)} /.netlify/functions/server-render 200\n`
)}
  `
  );
}

/**
 *
 * @param {{path: string; endsWithSplat: boolean}} route
 */
function toRoute(route) {
  return route.path;
}

run({
  renderFunctionFilePath: "./elm-stuff/elm-pages/elm.js",
  serverRoutes: [],
  fallbackRoutes: [{ path: "/:pokedexnumber", endsWithSplat: false }],
});
