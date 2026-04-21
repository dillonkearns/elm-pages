/**
 * Worker-thread entrypoint for BackendTask.Parallel.
 *
 * Two modes, selected by `workerData.workerKind`:
 *
 *   "js-port"     — used by `BackendTask.Parallel.run`. Loads the
 *                   project's `custom-backend-task` module once on
 *                   startup, then services tasks as
 *                     { taskId, portName, inputBytes, context }
 *                   from `parentPort.postMessage`. Responses go back as
 *                     { taskId, outputBytes } | { taskId, error }
 *
 *   "elm-script"  — used by `BackendTask.Parallel.worker` /
 *                   `Parallel.runOn`. Boots a compiled Elm worker script
 *                   in this thread (long-lived; loops via andThen) and
 *                   bridges the worker-side primitives
 *                   `initShared` / `receiveTask` / `sendResult` to
 *                   parent-thread messages:
 *                     - parent posts { tag: "task", taskId, inputBytes }
 *                     - worker posts { tag: "result", taskId, outputBytes }
 *
 * Workers are spawned by parallel-worker-pool.js and persist for the
 * lifetime of `elm-pages run` (or until the sub-pool is respawned).
 */

import { parentPort, workerData } from "node:worker_threads";
import * as url from "node:url";
import * as path from "node:path";

if (!parentPort) {
  throw new Error(
    "parallel-worker.js must be loaded as a Worker thread, not directly."
  );
}

const workerKind = (workerData && workerData.workerKind) || "js-port";

// Surface uncaught worker exceptions back to the parent before exiting so
// debugging the elm-script bridge isn't silent.
process.on("uncaughtException", (err) => {
  console.error(`[parallel-worker uncaughtException] ${err.stack || err}`);
});
process.on("unhandledRejection", (err) => {
  console.error(`[parallel-worker unhandledRejection] ${err && err.stack ? err.stack : err}`);
});

if (workerKind === "elm-script") {
  await runElmScriptWorker();
} else {
  await runJsPortWorker();
}

// ───────────────────────── js-port (default) ─────────────────────────

async function runJsPortWorker() {
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

      // Node structured-clones Buffer instances as Uint8Array across
      // worker boundaries, which strips Buffer-specific methods
      // (readUInt32BE, etc.). Restore a zero-copy Buffer view over the
      // same memory so port functions see the same type they would on
      // the main thread.
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
}

// ───────────────────────── elm-script ─────────────────────────

async function runElmScriptWorker() {
  const { compiledElmPath, workerModule, sharedBytes, portsPath, mode } =
    workerData;
  const sharedBuffer = bytesToBuffer(sharedBytes);

  // Lazily load the project's custom-backend-task + the request-cache so
  // the worker can resolve any non-`parallel-worker-*` BackendTask URL it
  // emits. This is the v1 path that lets a worker call e.g.
  // `InterpreterProject.load` (file IO, Cache.run, etc.) at startup
  // before entering its per-task loop. The per-task interface stays
  // pure Bytes-in / Bytes-out — only worker-internal setup uses the
  // wider BackendTask surface.
  let portsFile = null;
  if (portsPath) {
    try {
      portsFile = await import(url.pathToFileURL(path.resolve(portsPath)).href);
    } catch (e) {
      console.error(
        `[parallel elm-worker ${workerModule}] failed to load custom-backend-task: ${
          e && e.message ? e.message : e
        }`
      );
    }
  }
  const { lookupOrPerform } = await import("./request-cache.js");
  const { runInternalJob } = await import("./render.js");
  const fallbackMode = typeof mode === "string" ? mode : "build";
  // Patterns-to-watch is a render.js dev-server concept; in a worker
  // there's no dev-server file watcher to feed, so we hand
  // `runInternalJob` an inert Set that just absorbs writes.
  const inertWatchSet = new Set();

  // The sub-pool sends tasks as { tag: "task", taskId, inputBytes }.
  // We queue them until the Elm runtime's next `receiveTask` request
  // pulls one off, and remember which task is currently in flight so
  // the next `sendResult` knows which task to reply to.
  /** @type {Array<{ taskId: string, inputBuffer: Buffer }>} */
  const incomingTaskQueue = [];
  /** @type {((task: { taskId: string, inputBuffer: Buffer }) => void) | null} */
  let pendingReceive = null;
  /** @type {string | null} */
  let inFlightTaskId = null;

  parentPort.on("message", (msg) => {
    if (msg && msg.tag === "task") {
      const inputBuffer = bytesToBuffer(msg.inputBytes);
      const task = { taskId: msg.taskId, inputBuffer };
      if (pendingReceive) {
        const r = pendingReceive;
        pendingReceive = null;
        r(task);
      } else {
        incomingTaskQueue.push(task);
      }
    }
  });

  // Boot the compiled Elm worker app. The compiled module exposes
  // `Elm.WorkerMain_<workerModule>` (see commands/shared.js
  // `workerWrapperFile`).
  const elmFileUrl = url.pathToFileURL(path.resolve(compiledElmPath)).href;
  const warnOriginal = console.warn;
  console.warn = function () {};
  /** @type {any} */
  const elmModule = (await import(elmFileUrl)).default;
  console.warn = warnOriginal;

  const wrapperName = `WorkerMain_${workerModule}`;
  if (!elmModule.Elm[wrapperName]) {
    throw new Error(
      `Compiled worker module did not expose Elm.${wrapperName}. Got: ${Object.keys(
        elmModule.Elm
      ).join(", ")}`
    );
  }

  // The compatibilityKey is read by GeneratorApplication; mirroring the
  // value used by the main runGenerator path. We re-import it from the
  // generator's compiled JS so any version bump there stays in sync.
  const { compatibilityKey } = await import("./compatibility-key.js");

  const app = elmModule.Elm[wrapperName].init({
    flags: {
      compatibilityKey,
      argv: ["", `elm-pages worker ${workerModule}`],
      versionMessage: "",
      colorMode: false,
    },
  });

  app.ports.toJsPort.subscribe(async (newThing) => {
    let fromElm;
    let outgoingBytes = [];
    if ("json" in newThing) {
      fromElm = newThing.json;
      outgoingBytes = newThing.bytes || [];
    } else {
      fromElm = newThing;
    }

    if (typeof fromElm === "string") {
      // printAndExitSuccess (e.g. --help). Workers shouldn't be told to
      // print --help, so this is unexpected.
      console.error(
        `[parallel elm-worker ${workerModule}] unexpected printAndExitSuccess: ${fromElm}`
      );
      return;
    }
    if (fromElm.command === "log") {
      console.log(fromElm.value);
      return;
    }
    if (fromElm.tag === "ApiResponse") {
      // The Elm worker's BackendTask chain terminated. A well-formed
      // worker loops via andThen and never reaches ApiResponse.
      console.error(
        `[parallel elm-worker ${workerModule}] worker script terminated; expected an infinite loop via andThen.`
      );
      return;
    }
    if (fromElm.tag === "Errors") {
      const errorsJson = fromElm.args[0].errorsJson;
      const message =
        typeof errorsJson === "string" ? errorsJson : JSON.stringify(errorsJson);
      // Surface the error against whichever task is currently in flight
      // so the parent's runOn promise rejects rather than hanging.
      if (inFlightTaskId !== null) {
        parentPort.postMessage({
          tag: "error",
          taskId: inFlightTaskId,
          error: message,
        });
        inFlightTaskId = null;
      } else {
        console.error(
          `[parallel elm-worker ${workerModule}] error before any task: ${message}`
        );
      }
      return;
    }
    if (fromElm.tag !== "DoHttp") {
      console.error(
        `[parallel elm-worker ${workerModule}] unhandled toJsPort message: ${JSON.stringify(
          fromElm
        )}`
      );
      return;
    }

    const outgoingBytesMap = new Map(
      outgoingBytes.map(({ key, data }) => [key, dataViewToBuffer(data)])
    );

    const results = await Promise.all(
      fromElm.args[0].map(async ([requestHash, requestToPerform]) => {
        const reqBytes = outgoingBytesMap.get(requestHash);
        const u = requestToPerform.url;

        if (u === "elm-pages-internal://parallel-worker-init-shared") {
          // Worker's `initShared` request: respond with the cached
          // shared payload that was passed in via workerData.
          return bytesResponseEntry(requestHash, requestToPerform, sharedBuffer);
        }

        if (u === "elm-pages-internal://parallel-worker-receive-task") {
          // Worker's `receiveTask` request: hand it the next pending
          // task from the parent — blocking until one arrives.
          const task = await new Promise((resolve) => {
            const queued = incomingTaskQueue.shift();
            if (queued) {
              resolve(queued);
            } else {
              pendingReceive = resolve;
            }
          });
          inFlightTaskId = task.taskId;
          return bytesResponseEntry(
            requestHash,
            requestToPerform,
            task.inputBuffer
          );
        }

        if (u === "elm-pages-internal://parallel-worker-send-result") {
          // Worker's `sendResult` request: ship the bytes to the
          // parent and resolve with `()` (which decodes from empty
          // bytes).
          const outputBuffer = reqBytes || Buffer.alloc(0);
          if (inFlightTaskId === null) {
            console.error(
              `[parallel elm-worker ${workerModule}] sendResult called with no in-flight task.`
            );
          } else {
            parentPort.postMessage({
              tag: "result",
              taskId: inFlightTaskId,
              outputBytes: outputBuffer,
            });
            inFlightTaskId = null;
          }
          return bytesResponseEntry(
            requestHash,
            requestToPerform,
            Buffer.alloc(0)
          );
        }

        // Fall through to the standard request resolver so the worker
        // can handle file IO, BackendTask.Custom, http, glob, etc. on
        // its own thread (no main-thread round-trip). This is what
        // lets a worker do `InterpreterProject.load` at startup.
        //
        // Mirror render.js's split: internal `elm-pages-internal://*`
        // URLs (read-file, glob, now, env, stream, db-*, …) go through
        // `runInternalJob`; everything else (custom backend tasks,
        // bytes ports, http) goes through `lookupOrPerform`.
        try {
          const isInternalJob =
            u !== "elm-pages-internal://port" &&
            !u.startsWith("elm-pages-internal://port-bytes/") &&
            !u.startsWith("elm-pages-internal://parallel-port-bytes/") &&
            !u.startsWith("elm-pages-internal://parallel-spawn-worker/") &&
            !u.startsWith("elm-pages-internal://parallel-worker-task/") &&
            u.startsWith("elm-pages-internal://");

          if (isInternalJob) {
            const [, internalResult] = await runInternalJob(
              requestHash,
              app,
              requestToPerform,
              inertWatchSet,
              portsFile
            );
            return {
              key: requestHash,
              json: {
                request: internalResult.request,
                response: internalResult.response,
              },
              bytes: internalResult.rawBytes
                ? bufferToDataView(internalResult.rawBytes)
                : null,
            };
          }

          const lookupResponse = await lookupOrPerform(
            portsFile,
            fallbackMode,
            requestToPerform
          );
          if (lookupResponse.kind === "response-json") {
            return {
              key: requestHash,
              json: {
                request: requestToPerform,
                response: lookupResponse.value,
              },
              bytes: lookupResponse.rawBytes
                ? bufferToDataView(lookupResponse.rawBytes)
                : null,
            };
          }
          if (lookupResponse.kind === "cache-response-path") {
            const responseJson = JSON.parse(
              await (
                await import("node:fs/promises")
              ).readFile(lookupResponse.value, "utf8")
            );
            return {
              key: requestHash,
              json: { request: requestToPerform, response: responseJson },
              bytes: null,
            };
          }
          throw new Error(
            `[parallel elm-worker ${workerModule}] lookupOrPerform returned unexpected kind: ${lookupResponse.kind}`
          );
        } catch (lookupError) {
          const message =
            lookupError instanceof Error
              ? lookupError.message
              : typeof lookupError === "object"
              ? JSON.stringify(lookupError)
              : String(lookupError);
          return {
            key: requestHash,
            json: {
              request: requestToPerform,
              response: {
                statusCode: 500,
                statusText: "Internal Error",
                headers: {},
                url: requestToPerform.url,
                bodyKind: "string",
                body: message,
              },
            },
            bytes: null,
          };
        }
      })
    );

    app.ports.gotBatchSub.send(results);
  });
}

function bytesResponseEntry(requestHash, requestToPerform, buffer) {
  return {
    key: requestHash,
    json: {
      request: requestToPerform,
      response: { bodyKind: "bytes", body: null },
    },
    bytes: bufferToDataView(buffer),
  };
}

function bufferToDataView(buf) {
  return new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
}

function dataViewToBuffer(dv) {
  return Buffer.from(dv.buffer, dv.byteOffset, dv.byteLength);
}

function bytesToBuffer(bytes) {
  if (Buffer.isBuffer(bytes)) return bytes;
  if (bytes instanceof Uint8Array) {
    return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }
  if (bytes instanceof ArrayBuffer) return Buffer.from(bytes);
  if (bytes && typeof bytes === "object" && "buffer" in bytes) {
    return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }
  // Empty / null payload — represent as zero-length buffer so the Elm
  // side decodes successfully against e.g. `Bytes.Decode.succeed ()`.
  return Buffer.alloc(0);
}
