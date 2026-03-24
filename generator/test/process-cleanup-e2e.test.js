/**
 * End-to-end test for graceful child process cleanup.
 *
 * Runs a real elm-pages script (SleepForever.elm) that spawns `sleep 31415`
 * via BackendTask.Stream, then sends SIGTERM to the elm-pages process and
 * verifies that the child sleep process is also killed.
 *
 * Prerequisites: lamdera on PATH, examples/end-to-end set up (npm ci).
 * Skips automatically if prerequisites aren't met.
 * Explicitly run in CI via test.sh after examples/end-to-end setup.
 */

import { describe, it, expect, afterEach } from "vitest";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import * as path from "node:path";
import * as fs from "node:fs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "../..");
const cliPath = path.join(repoRoot, "generator", "src", "cli.js");
const e2eDir = path.join(repoRoot, "examples", "end-to-end");
const SLEEP_MARKER = "31415";

// Check prerequisites at module level (synchronous)
const hasLamdera =
  spawnSync("which", ["lamdera"], { encoding: "utf8" }).status === 0;
const hasE2eSetup = fs.existsSync(path.join(e2eDir, "node_modules"));

function isProcessAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function findProcessPid(pattern) {
  try {
    const result = spawnSync("pgrep", ["-f", pattern], { encoding: "utf8" });
    if (result.status !== 0) return null;
    const pids = result.stdout
      .trim()
      .split("\n")
      .filter(Boolean)
      .map(Number);
    return pids.length > 0 ? pids[0] : null;
  } catch {
    return null;
  }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function waitForExit(proc) {
  return new Promise((resolve) => {
    if (proc.exitCode !== null) return resolve(proc.exitCode);
    proc.on("exit", (code) => resolve(code));
  });
}

async function waitForProcess(pattern, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const pid = findProcessPid(pattern);
    if (pid) return pid;
    await delay(250);
  }
  return null;
}

describe.skipIf(!hasLamdera || !hasE2eSetup)(
  "Process cleanup E2E",
  () => {
    let activeProc = null;

    afterEach(() => {
      // Kill the elm-pages process if still running
      if (activeProc && activeProc.exitCode === null) {
        activeProc.kill("SIGKILL");
      }
      activeProc = null;
      // Kill any surviving sleep processes with our marker
      try {
        spawnSync("pkill", ["-f", `sleep ${SLEEP_MARKER}`], {
          stdio: "ignore",
        });
      } catch {}
    });

    it(
      "SIGTERM kills child processes spawned via BackendTask.Stream",
      async () => {
        // Start elm-pages run — this compiles the Elm script then spawns sleep
        activeProc = spawn(
          process.execPath,
          [cliPath, "run", "script/src/SleepForever.elm"],
          {
            cwd: e2eDir,
            stdio: ["ignore", "pipe", "pipe"],
          }
        );

        // Wait for the sleep process to appear (Elm compilation may take a while)
        const sleepPid = await waitForProcess(
          `sleep ${SLEEP_MARKER}`,
          90_000
        );
        expect(sleepPid, "sleep process should have been spawned").toBeTruthy();
        expect(isProcessAlive(sleepPid)).toBe(true);

        // Send SIGTERM to the elm-pages process
        activeProc.kill("SIGTERM");
        await waitForExit(activeProc);

        // Give child a moment to receive SIGTERM and die
        await delay(500);

        // With the fix: sleep should be dead
        expect(
          isProcessAlive(sleepPid),
          "sleep process should have been killed by SIGTERM handler"
        ).toBe(false);
      },
      120_000
    );
  }
);
