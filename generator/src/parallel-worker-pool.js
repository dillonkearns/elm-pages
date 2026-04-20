/**
 * Long-lived Node Worker-thread pool for BackendTask.Parallel.run.
 *
 * The pool is lazily initialized on the first `dispatch` call and torn down
 * when the process exits. Pool size defaults to `os.cpus().length`. Tasks are
 * distributed round-robin across workers; each worker services one task at a
 * time and queues subsequent dispatches if all workers are busy.
 *
 * Usage:
 *   import * as pool from "./parallel-worker-pool.js";
 *   pool.configure({ portsPath });
 *   const outputBytes = await pool.dispatch(portName, inputBytes, context);
 */

import { Worker } from "node:worker_threads";
import * as os from "node:os";
import * as path from "node:path";
import * as url from "node:url";

const __filename = url.fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const WORKER_ENTRY = path.join(__dirname, "parallel-worker.js");

// Module-level state: pool of persistent workers and configuration.
let config = { portsPath: null, poolSize: null };
let workers = null; // Array<{ worker: Worker, busy: boolean, taskId: string | null, resolve: Function | null, reject: Function | null }>
let taskQueue = []; // Array<{ portName, inputBytes, context, resolve, reject }>
let nextTaskId = 0;

/**
 * Configure the pool before first use. Must be called once from the
 * command runner with the compiled custom-backend-task path.
 *
 * @param {{ portsPath: string | null, poolSize?: number }} options
 */
export function configure({ portsPath, poolSize }) {
  config.portsPath = portsPath;
  if (typeof poolSize === "number" && poolSize > 0) {
    config.poolSize = poolSize;
  }
}

function ensurePool() {
  if (workers !== null) return;
  const size =
    config.poolSize ||
    Math.max(1, Math.min(os.cpus().length, 16));
  workers = [];
  for (let i = 0; i < size; i++) {
    const worker = new Worker(WORKER_ENTRY, {
      workerData: { portsPath: config.portsPath },
      // Workers inherit the parent env; this mirrors how render workers
      // are spawned in build.js (SHARE_ENV). Parallel workers need the
      // same process.env visibility so port functions that read env vars
      // behave identically to the main-thread Custom.runBytes path.
      env: process.env,
    });
    const entry = {
      worker,
      busy: false,
      taskId: null,
      resolve: null,
      reject: null,
    };
    worker.on("message", (msg) => handleResult(entry, msg));
    worker.on("error", (err) => {
      // A worker thread error while no task is in flight is logged; otherwise
      // it fails the active task.
      if (entry.busy && entry.reject) {
        const reject = entry.reject;
        entry.busy = false;
        entry.taskId = null;
        entry.resolve = null;
        entry.reject = null;
        reject(err);
      } else {
        console.error("[parallel worker] uncaught error:", err);
      }
      // Try to drain the queue on the remaining workers.
      pumpQueue();
    });
    worker.on("exit", (code) => {
      if (code !== 0) {
        console.error(
          `[parallel worker] unexpectedly exited with code ${code}`
        );
      }
    });
    workers.push(entry);
  }
}

function handleResult(entry, msg) {
  const { taskId, outputBytes, error } = msg;
  if (!entry.busy || entry.taskId !== taskId) {
    // Stale message; ignore.
    return;
  }
  const { resolve, reject } = entry;
  entry.busy = false;
  entry.taskId = null;
  entry.resolve = null;
  entry.reject = null;
  if (error !== undefined) {
    reject(new Error(error));
  } else {
    resolve(outputBytes);
  }
  pumpQueue();
}

function pumpQueue() {
  while (taskQueue.length > 0) {
    const free = workers.find((w) => !w.busy);
    if (!free) return;
    const task = taskQueue.shift();
    assign(free, task);
  }
}

function assign(entry, task) {
  const taskId = String(nextTaskId++);
  entry.busy = true;
  entry.taskId = taskId;
  entry.resolve = task.resolve;
  entry.reject = task.reject;
  entry.worker.postMessage({
    taskId,
    portName: task.portName,
    inputBytes: task.inputBytes,
    context: task.context,
  });
}

/**
 * Dispatch a task to the pool. Returns a Promise that resolves with the
 * Buffer returned by the port function.
 *
 * @param {string} portName
 * @param {Buffer} inputBytes
 * @param {object} context
 * @returns {Promise<Buffer>}
 */
export function dispatch(portName, inputBytes, context) {
  ensurePool();
  return new Promise((resolve, reject) => {
    const task = { portName, inputBytes, context, resolve, reject };
    const free = workers.find((w) => !w.busy);
    if (free) {
      assign(free, task);
    } else {
      taskQueue.push(task);
    }
  });
}

/**
 * Terminate all workers. Called on process shutdown.
 */
export async function shutdown() {
  if (workers === null) return;
  await Promise.all(workers.map((w) => w.worker.terminate()));
  workers = null;
}
