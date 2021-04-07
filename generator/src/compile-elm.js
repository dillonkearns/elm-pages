const spawnCallback = require("cross-spawn").spawn;
const fs = require("fs");
const path = require("path");
const debug = true;

function spawnElmMake(elmEntrypointPath, outputPath, cwd) {
  return new Promise((resolve, reject) => {
    const fullOutputPath = cwd ? path.join(cwd, outputPath) : outputPath;
    const subprocess = runElm(elmEntrypointPath, outputPath, cwd);

    subprocess.on("close", (code) => {
      const fileOutputExists = fs.existsSync(fullOutputPath);
      const elmFileContent = fs.readFileSync(fullOutputPath, "utf-8");

      fs.writeFileSync(
        fullOutputPath,
        elmFileContent.replace(
          /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
          "return " + (debug ? "_Json_wrap(x)" : "x")
        )
      );
      if (code == 0 && fileOutputExists) {
        resolve();
      } else {
        reject();
      }
    });
  });
}

function runElm(elmEntrypointPath, outputPath, cwd) {
  console.log("Running elm make");
  return spawnCallback(
    `elm`,
    ["make", elmEntrypointPath, "--output", outputPath, "--debug"],
    {
      // ignore stdout
      stdio: ["inherit", "ignore", "inherit"],
      cwd: cwd,
    }
  );
}

module.exports = {
  spawnElmMake,
};
