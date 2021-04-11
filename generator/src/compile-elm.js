const spawnCallback = require("cross-spawn").spawn;
const fs = require("fs");
const path = require("path");
const kleur = require("kleur");
const debug = true;

async function spawnElmMake(elmEntrypointPath, outputPath, cwd) {
  const fullOutputPath = cwd ? path.join(cwd, outputPath) : outputPath;
  await runElm(elmEntrypointPath, outputPath, cwd);

  const elmFileContent = await fs.promises.readFile(fullOutputPath, "utf-8");

  await fs.promises.writeFile(
    fullOutputPath,
    elmFileContent.replace(
      /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
      "return " + (debug ? "_Json_wrap(x)" : "x")
    )
  );
}

/**
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string} [ cwd ]
 */
async function runElm(elmEntrypointPath, outputPath, cwd) {
  const startTime = Date.now();
  console.log(`elm make ${elmEntrypointPath}`);
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

module.exports = {
  spawnElmMake,
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
