const spawnCallback = require("cross-spawn").spawn;
const fs = require("fs");
const path = require("path");

function spawnElmMake(elmEntrypointPath, outputPath, cwd) {
  return new Promise((resolve, reject) => {
    const fullOutputPath = cwd ? path.join(cwd, outputPath) : outputPath;
    const subprocess = runElm(elmEntrypointPath, outputPath, cwd);

    subprocess.on("close", (code) => {
      const fileOutputExists = fs.existsSync(fullOutputPath);
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
