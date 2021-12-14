const spawnCallback = require("cross-spawn").spawn;
const fs = require("fs");
const path = require("path");
const kleur = require("kleur");
const debug = true;
const { inject } = require("elm-hot");
const pathToClientElm = path.join(
  process.cwd(),
  "elm-stuff/elm-pages/",
  "browser-elm.js"
);

async function spawnElmMake(elmEntrypointPath, outputPath, cwd) {
  const fullOutputPath = cwd ? path.join(cwd, outputPath) : outputPath;
  await runElm(elmEntrypointPath, outputPath, cwd);

  await fs.promises.writeFile(
    fullOutputPath,
    (await fs.promises.readFile(fullOutputPath, "utf-8"))
      .replace(
        /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
        "return " + (debug ? "_Json_wrap(x)" : "x")
      )
      .replace(
        "return ports ? { ports: ports } : {};",
        `const die = function() {
        managers = null
        model = null
        stepper = null
        ports = null
      }

      return ports ? { ports: ports, die: die } : { die: die };`
      )
  );
}

async function compileElmForBrowser() {
  await runElm("./.elm-pages/TemplateModulesBeta.elm", pathToClientElm);
  return fs.promises.writeFile(
    "./.elm-pages/cache/elm.js",
    inject(await fs.promises.readFile(pathToClientElm, "utf-8"))
  );
}

/**
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string} [ cwd ]
 */
async function runElm(elmEntrypointPath, outputPath, cwd) {
  const startTime = Date.now();
  return new Promise((resolve, reject) => {
    const child = spawnCallback(
      `elm`,
      [
        "make",
        elmEntrypointPath,
        "--output",
        outputPath,
        "--debug",
        "--report",
        "json",
      ],
      { cwd: cwd }
    );

    let scriptOutput = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.on("close", function (code) {
      if (code === 0) {
        console.log(
          `Ran elm make ${elmEntrypointPath} in ${timeFrom(startTime)}`
        );
        resolve();
      } else {
        reject(scriptOutput);
      }
    });
  });
}

/**
 * @param {string} [ cwd ]
 */
async function runElmReview(cwd) {
  const startTime = Date.now();
  return new Promise((resolve, reject) => {
    const child = spawnCallback(
      `elm-review`,
      [
        "--report",
        "json",
        "--namespace",
        "elm-pages",
        "--config",
        path.join(__dirname, "../../generator/review"),
      ],
      { cwd: cwd }
    );

    let scriptOutput = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.on("close", function (code) {
      console.log(`Ran elm-review in ${timeFrom(startTime)}`);
      if (code === 0) {
        resolve(scriptOutput);
      } else {
        resolve(scriptOutput);
      }
    });
  });
}

module.exports = {
  spawnElmMake,
  compileElmForBrowser,
  runElmReview,
};

/**
 * @param {number} start
 * @param {number} subtract
 */
function timeFrom(start, subtract = 0) {
  const time = Date.now() - start - subtract;
  const timeString = (time + `ms`).padEnd(5, " ");
  if (time < 10) {
    return kleur.green(timeString);
  } else if (time < 50) {
    return kleur.yellow(timeString);
  } else {
    return kleur.red(timeString);
  }
}
