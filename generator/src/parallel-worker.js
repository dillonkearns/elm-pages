/**
 * Worker-thread entrypoint for BackendTask.Parallel.run.
 *
 * Each worker loads the project's custom-backend-task module once on startup
 * and then services tasks in a loop. Tasks arrive as
 *   { taskId, portName, inputBytes, context }
 * via parentPort.postMessage and responses go back as
 *   { taskId, outputBytes }   // on success
 *   { taskId, error }         // on failure
 *
 * Workers are spawned by parallel-worker-pool.js and persist for the lifetime
 * of `elm-pages run`.
 */

import { parentPort, workerData } from "node:worker_threads";
import * as url from "node:url";
import * as path from "node:path";

if (!parentPort) {
  throw new Error(
    "parallel-worker.js must be loaded as a Worker thread, not directly."
  );
}

// Load the project's compiled custom-backend-task module. Fires once per
// worker; all task dispatches share this module reference in-worker.
let portsFile = null;
let portsLoadError = null;
if (workerData && workerData.portsPath) {
  try {
    const portsUrl = url
      .pathToFileURL(path.resolve(workerData.portsPath))
      .href;
    portsFile = await import(portsUrl);
  } catch (e) {
    portsLoadError = e;
  }
}

parentPort.on("message", async (message) => {
  const { taskId, portName, inputBytes, context } = message;
  try {
    if (portsLoadError) {
      throw new Error(
        "Failed to import custom-backend-task module in worker: " +
          portsLoadError.message
      );
    }
    if (portsFile === null) {
      throw new Error(
        "No custom-backend-task module available in worker (no portsPath passed)."
      );
    }
    if (!portsFile[portName]) {
      throw new Error(
        `No export named \`${portName}\` in custom-backend-task module.`
      );
    }
    if (typeof portsFile[portName] !== "function") {
      throw new Error(
        `Export \`${portName}\` is not a function (found ${typeof portsFile[
          portName
        ]}).`
      );
    }

    // Node structured-clones Buffer instances as Uint8Array across worker
    // boundaries, which strips Buffer-specific methods (readUInt32BE, etc.).
    // Restore a zero-copy Buffer view over the same memory so port functions
    // see the same type they would on the main thread.
    const inputBuffer = Buffer.isBuffer(inputBytes)
      ? inputBytes
      : Buffer.from(
          inputBytes.buffer,
          inputBytes.byteOffset,
          inputBytes.byteLength
        );

    const result = await portsFile[portName](inputBuffer, context);

    let outputBuffer;
    if (Buffer.isBuffer(result)) {
      outputBuffer = result;
    } else if (result instanceof Uint8Array) {
      outputBuffer = Buffer.from(
        result.buffer,
        result.byteOffset,
        result.byteLength
      );
    } else if (result instanceof ArrayBuffer) {
      outputBuffer = Buffer.from(result);
    } else {
      throw new Error(
        `Port \`${portName}\` must return Bytes (Buffer/Uint8Array/ArrayBuffer). Got: ${typeof result}`
      );
    }

    parentPort.postMessage({ taskId, outputBytes: outputBuffer });
  } catch (err) {
    parentPort.postMessage({
      taskId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
});
