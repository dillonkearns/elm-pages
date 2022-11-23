const spawnCallback = require("cross-spawn").spawn;

function runElmCodegenInstall() {
  return new Promise(async (resolve, reject) => {
    const subprocess = spawnCallback(`elm-codegen`, ["install"], {
      // ignore stdout
      // stdio: ["inherit", "ignore", "inherit"],
      //       cwd: cwd,
    });
    //     if (await fsHelpers.fileExists(outputPath)) {
    //       await fsPromises.unlink(outputPath, {
    //         force: true /* ignore errors if file doesn't exist */,
    //       });
    //     }
    let commandOutput = "";

    subprocess.stderr.on("data", function (data) {
      commandOutput += data;
    });
    subprocess.stdout.on("data", function (data) {
      commandOutput += data;
    });
    subprocess.on("error", function () {
      reject(commandOutput);
    });

    subprocess.on("close", async (code) => {
      if (code == 0) {
        resolve();
      } else {
        reject(commandOutput);
      }
    });
  });
}

module.exports = { runElmCodegenInstall };
