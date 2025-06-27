import { spawn as spawnCallback } from "cross-spawn";
import which from "which";

/**
 * @returns {Promise<{ success: true } | { success: false; message: string; error?: Error }>}
 */
export async function runElmCodegenInstall() {
  try {
    await which("elm-codegen");
  } catch (error) {
    return { success: false, message: "Unable to find elm-codegen on the PATH" };
  }

  return new Promise((resolve) => {
    const subprocess = spawnCallback("elm-codegen", ["install"]);

    let commandOutput = "";
    subprocess.stderr.on("data", function (data) {
      commandOutput += data;
    });
    subprocess.stdout.on("data", function (data) {
      commandOutput += data;
    });
    subprocess.on("error", function (error) {
      resolve({ success: false, message: "Failed to run elm-codegen", error });
    });

    subprocess.on("close", (code) => {
      if (code === 0) {
        return resolve({ success: true });
      }
      resolve({
        success: false,
        message: `elm-codegen exited with code ${code}`,
        error: commandOutput.length > 0 ? new Error(commandOutput) : undefined
      });
    });
  });
}
