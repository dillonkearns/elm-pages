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
let config = {
  portsPath: null,
  poolSize: null,
  projectDirectory: null,
};
let workers = null; // Array<{ worker: Worker, busy: boolean, taskId: string | null, resolve: Function | null, reject: Function | null }>
let taskQueue = []; // Array<{ portName, inputBytes, context, resolve, reject }>
let nextTaskId = 0;

// Elm-in-worker state: one sub-pool per `BackendTask.Parallel.worker`
// module. Each sub-pool has its own worker threads (each running a
// compiled Elm script) and its own task queue. The compile result for a
// module is cached per process — once `ensureWorkerCompiled` runs for X,
// later `Parallel.worker` calls reuse the same `.cjs`.
const elmSubPools = new Map(); // workerModule -> { workers, queue, sharedBytes, compiledElmPath }
const compiledWorkerCache = new Map(); // workerModule -> Promise<string>

// Lazy-spawn state: `BackendTask.Parallel.worker` registers a config here
// without creating workers. The actual pool only spawns on the first
// `Parallel.runOn` for that module. Runs whose test evals are all cache
// hits (via `Cache.computeAsync` in the TestRunner pipeline) never
// trigger `dispatchElmTask`, so the worker pool stays idle and we skip
// compile + load + worker-boot entirely.
const pendingElmPools = new Map(); // workerModule -> { sharedBytes }
const inFlightSpawns = new Map(); // workerModule -> Promise<void>

/**
 * Configure the pool before first use. Called once from the command
 * runner so the pool can spawn workers that share the project's
 * custom-backend-task module and (for Elm-in-worker) reach the project
 * directory for on-demand worker-script compilation.
 *
 * @param {{ portsPath: string | null, poolSize?: number, projectDirectory?: string }} options
 */
export function configure({ portsPath, poolSize, projectDirectory }) {
  config.portsPath = portsPath;
  if (typeof poolSize === "number" && poolSize > 0) {
    config.poolSize = poolSize;
  }
  if (typeof projectDirectory === "string") {
    config.projectDirectory = projectDirectory;
  }
}

/**
 * Resolve the worker pool size, honoring (in order) an explicit
 * `configure({ poolSize })` call, the `ELM_PAGES_PARALLEL_POOL_SIZE`
 * environment variable, and finally falling back to `min(cpus, 16)`.
 *
 * Per-call CPU bookkeeping, NOT cached — the env var can change between
 * `Parallel.run` and `Parallel.worker` invocations within one process,
 * which is useful for ad-hoc benchmarks (`POOL_SIZE=2 npm run bench`).
 */
function resolvePoolSize() {
  if (typeof config.poolSize === "number" && config.poolSize > 0) {
    return config.poolSize;
  }
  const envOverride = Number(process.env.ELM_PAGES_PARALLEL_POOL_SIZE);
  if (Number.isFinite(envOverride) && envOverride > 0) {
    return Math.floor(envOverride);
  }
  return Math.max(1, Math.min(os.cpus().length, 16));
}

function ensurePool() {
  if (workers !== null) return;
  const size = resolvePoolSize();
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
 * Terminate all workers (both js-port and elm-script sub-pools). Called
 * on process shutdown.
 */
export async function shutdown() {
  const teardown = [];
  if (workers !== null) {
    teardown.push(...workers.map((w) => w.worker.terminate()));
    workers = null;
  }
  for (const sub of elmSubPools.values()) {
    teardown.push(...sub.workers.map((w) => w.worker.terminate()));
  }
  elmSubPools.clear();
  pendingElmPools.clear();
  inFlightSpawns.clear();
  compiledWorkerCache.clear();
  await Promise.all(teardown);
}

// ───────────────────────── Elm-in-worker helpers ─────────────────────────

/**
 * Compile the worker module exactly once per process. Concurrent
 * `Parallel.worker` calls for the same module share a single in-flight
 * compile via a Promise cache.
 *
 * @param {string} workerModule
 * @returns {Promise<string>} absolute path to the compiled `.cjs`
 */
function ensureWorkerCompiled(workerModule) {
  let pending = compiledWorkerCache.get(workerModule);
  if (pending) return pending;
  if (!config.projectDirectory) {
    return Promise.reject(
      new Error(
        "parallel-worker-pool not configured with projectDirectory; cannot compile Elm worker " +
          workerModule
      )
    );
  }
  pending = (async () => {
    const { compileWorkerScript } = await import("./commands/shared.js");
    return await compileWorkerScript(workerModule, config.projectDirectory);
  })();
  compiledWorkerCache.set(workerModule, pending);
  // If the compile fails, drop the entry so a retry is possible.
  pending.catch(() => {
    compiledWorkerCache.delete(workerModule);
  });
  return pending;
}

/**
 * Register the Elm-in-worker pool configuration for a given module —
 * **without** actually spawning workers or compiling the worker script.
 * The first `dispatchElmTask` call for this module triggers the real
 * spawn (`actuallySpawnElmPool` below).
 *
 * Called from the `parallel-spawn-worker/X` URL handler when the main
 * script evaluates `BackendTask.Parallel.worker { workerModule, shared }`.
 *
 * Rationale: after the Cache.run + worker dispatch integration
 * (commit `95927ed`), warm reruns often hit the on-disk cache for
 * every test and never actually dispatch to a worker. With the
 * previous eager-spawn, every run paid the worker-pool spawn cost
 * (compile-cached, ~300 ms + per-worker load) even when no `runOn`
 * fired. Lazy spawn eliminates that cost for warm-only runs — closes
 * the NEW-vs-OLD warm gap on core-extra (2.7 s → ~2.5 s) and
 * elm-markdown (1.95 s → ~1.7 s).
 *
 * Re-registering for the same module tears down any already-spawned
 * pool so the next dispatch picks up the new `sharedBytes`.
 *
 * @param {{ workerModule: string, sharedBytes: Buffer }} options
 * @returns {Promise<void>}
 */
export async function spawnElmWorkerPool({ workerModule, sharedBytes }) {
  // Tear down any pre-existing sub-pool for this module (idempotent
  // if no prior pool existed). This happens immediately because the
  // old pool might still be holding memory / worker threads we don't
  // want to carry forward under a new shared payload.
  const previous = elmSubPools.get(workerModule);
  if (previous) {
    await Promise.all(previous.workers.map((w) => w.worker.terminate()));
    for (const task of previous.queue) {
      task.reject(
        new Error(
          `Elm worker pool for "${workerModule}" was respawned before this task ran.`
        )
      );
    }
    elmSubPools.delete(workerModule);
  }

  // Record the config; actual worker spawn is deferred to the first
  // dispatch via `ensureElmWorkerPoolSpawned`.
  pendingElmPools.set(workerModule, { sharedBytes });
}

/**
 * If the pool for `workerModule` isn't running yet but has a pending
 * registration, spawn it now. Idempotent + concurrent-safe: multiple
 * simultaneous `dispatchElmTask` calls dedupe on a shared in-flight
 * Promise so the pool is only spawned once.
 */
function ensureElmWorkerPoolSpawned(workerModule) {
  if (elmSubPools.has(workerModule)) {
    return Promise.resolve();
  }
  const inFlight = inFlightSpawns.get(workerModule);
  if (inFlight) {
    return inFlight;
  }
  const pending = pendingElmPools.get(workerModule);
  if (!pending) {
    return Promise.reject(
      new Error(
        `No Elm worker pool registered for "${workerModule}". Call BackendTask.Parallel.worker before runOn.`
      )
    );
  }
  const spawnPromise = actuallySpawnElmPool(workerModule, pending.sharedBytes);
  inFlightSpawns.set(workerModule, spawnPromise);
  spawnPromise
    .then(() => {
      inFlightSpawns.delete(workerModule);
      pendingElmPools.delete(workerModule);
    })
    .catch(() => {
      // On failure, drop the in-flight entry so a retry can re-attempt.
      inFlightSpawns.delete(workerModule);
    });
  return spawnPromise;
}

async function actuallySpawnElmPool(workerModule, sharedBytes) {
  const compiledElmPath = await ensureWorkerCompiled(workerModule);

  const size = resolvePoolSize();
  const sub = { workers: [], queue: [] };
  for (let i = 0; i < size; i++) {
    const worker = new Worker(WORKER_ENTRY, {
      workerData: {
        workerKind: "elm-script",
        compiledElmPath,
        workerModule,
        sharedBytes,
        portsPath: config.portsPath,
        mode: "build",
      },
      env: process.env,
    });
    const entry = {
      worker,
      busy: false,
      taskId: null,
      resolve: null,
      reject: null,
    };
    worker.on("message", (msg) => handleElmResult(sub, entry, msg));
    worker.on("error", (err) => {
      if (entry.busy && entry.reject) {
        const reject = entry.reject;
        entry.busy = false;
        entry.taskId = null;
        entry.resolve = null;
        entry.reject = null;
        reject(err);
      } else {
        console.error(
          `[parallel elm-worker ${workerModule}] uncaught error:`,
          err
        );
      }
      pumpElmQueue(sub);
    });
    worker.on("exit", (code) => {
      if (code !== 0) {
        console.error(
          `[parallel elm-worker ${workerModule}] unexpectedly exited with code ${code}`
        );
      }
    });
    sub.workers.push(entry);
  }
  elmSubPools.set(workerModule, sub);
}

/**
 * Dispatch a single per-task input to a free worker in the sub-pool for
 * the given module. If the pool was registered by `spawnElmWorkerPool`
 * but hasn't been spawned yet (lazy spawn — see that function's doc),
 * the first `dispatchElmTask` call triggers the actual compile + worker
 * boot. The promise resolves with the bytes the worker passed back via
 * `Parallel.sendResult`.
 *
 * @param {{ workerModule: string, inputBytes: Buffer }} options
 * @returns {Promise<Buffer>}
 */
export async function dispatchElmTask({ workerModule, inputBytes }) {
  await ensureElmWorkerPoolSpawned(workerModule);
  const sub = elmSubPools.get(workerModule);
  if (!sub) {
    throw new Error(
      `No Elm worker pool for "${workerModule}" after spawn; internal bookkeeping error.`
    );
  }
  return new Promise((resolve, reject) => {
    const task = { inputBytes, resolve, reject };
    const free = sub.workers.find((w) => !w.busy);
    if (free) {
      assignElmTask(free, task);
    } else {
      sub.queue.push(task);
    }
  });
}

function assignElmTask(entry, task) {
  const taskId = String(nextTaskId++);
  entry.busy = true;
  entry.taskId = taskId;
  entry.resolve = task.resolve;
  entry.reject = task.reject;
  task._assignedAt = Date.now();
  if (process.env.ELM_PAGES_PARALLEL_DEBUG) {
    console.error(`[pool] assign task ${taskId} at +${task._assignedAt - poolStart}ms`);
  }
  entry.worker.postMessage({
    tag: "task",
    taskId,
    inputBytes: task.inputBytes,
  });
}

const poolStart = Date.now();

function handleElmResult(sub, entry, msg) {
  if (msg && msg.tag === "result") {
    if (!entry.busy || entry.taskId !== msg.taskId) return; // stale
    const { resolve } = entry;
    if (process.env.ELM_PAGES_PARALLEL_DEBUG) {
      console.error(`[pool] result task ${msg.taskId} at +${Date.now() - poolStart}ms`);
    }
    entry.busy = false;
    entry.taskId = null;
    entry.resolve = null;
    entry.reject = null;
    resolve(msg.outputBytes);
    pumpElmQueue(sub);
  } else if (msg && msg.tag === "error") {
    if (!entry.busy || entry.taskId !== msg.taskId) return;
    const { reject } = entry;
    entry.busy = false;
    entry.taskId = null;
    entry.resolve = null;
    entry.reject = null;
    reject(new Error(msg.error));
    pumpElmQueue(sub);
  }
  // Other tags (e.g. log) are ignored here; the worker can stdout
  // directly.
}

function pumpElmQueue(sub) {
  while (sub.queue.length > 0) {
    const free = sub.workers.find((w) => !w.busy);
    if (!free) return;
    assignElmTask(free, sub.queue.shift());
  }
}
