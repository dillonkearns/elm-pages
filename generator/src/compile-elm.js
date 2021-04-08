const spawnCallback = require("cross-spawn").spawn;
const fs = require("fs");
const path = require("path");
const debug = true;

async function spawnElmMake(elmEntrypointPath, outputPath, cwd) {
  const fullOutputPath = cwd ? path.join(cwd, outputPath) : outputPath;
  await runElm(elmEntrypointPath, outputPath, cwd);

  const elmFileContent = fs.readFileSync(fullOutputPath, "utf-8");

  fs.writeFileSync(
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
  console.log("Running elm make");
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
