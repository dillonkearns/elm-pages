/**
 * E2E tests for graceful child process cleanup on exit.
 *
 * Each test spawns a real Node process that itself spawns `sleep 600`,
 * then verifies whether the child is cleaned up when the parent exits.
 */

import { describe, it, expect, afterEach } from "vitest";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import * as path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE = path.join(__dirname, "fixtures", "spawn-and-exit.mjs");

function isProcessAlive(pid) {
  try {
    process.kill(pid, 0); // signal 0 = existence check
    return true;
  } catch {
    return false;
  }
}

function killIfAlive(pid) {
  try {
    process.kill(pid, "SIGKILL");
  } catch {}
}

/**
 * Spawn the fixture helper and return { childPid, exitCode, proc }.
 * Reads the child PID from the helper's stdout JSON line.
 */
function runFixture(mode) {
  return new Promise((resolve, reject) => {
    const proc = spawn("node", [FIXTURE, mode], {
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    proc.stdout.on("data", (chunk) => { stdout += chunk; });

    let stderr = "";
    proc.stderr.on("data", (chunk) => { stderr += chunk; });

    proc.on("error", reject);
    proc.on("exit", (code) => {
      try {
        const line = stdout.trim().split("\n")[0];
        const { childPid } = JSON.parse(line);
        resolve({ childPid, exitCode: code, stderr });
      } catch (e) {
        reject(new Error(`Failed to parse fixture output: ${stdout}\nstderr: ${stderr}\n${e}`));
      }
    });
  });
}

/** Spawn fixture but don't wait for exit — returns the live process + a childPid promise. */
function runFixtureLive(mode) {
  const proc = spawn("node", [FIXTURE, mode], {
    stdio: ["ignore", "pipe", "pipe"],
  });

  let stdout = "";
  const childPidPromise = new Promise((resolve, reject) => {
    proc.stdout.on("data", (chunk) => {
      stdout += chunk;
      // Try to parse as soon as we get the JSON line
      try {
        const line = stdout.trim().split("\n")[0];
        const { childPid } = JSON.parse(line);
        resolve(childPid);
      } catch {}
    });
    proc.on("error", reject);
    // If process exits before we get PID, reject
    proc.on("exit", () => {
      try {
        const line = stdout.trim().split("\n")[0];
        const { childPid } = JSON.parse(line);
        resolve(childPid);
      } catch (e) {
        reject(new Error(`Fixture exited before emitting childPid: ${stdout}`));
      }
    });
  });

  return { proc, childPidPromise };
}

function waitForExit(proc) {
  return new Promise((resolve) => {
    proc.on("exit", (code) => resolve(code));
  });
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForProcessDeath(pid, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (!isProcessAlive(pid)) return true;
    await delay(50);
  }
  return !isProcessAlive(pid);
}

describe("Child process cleanup on exit", () => {
  const pidsToCleanup = [];

  afterEach(() => {
    // Kill any surviving orphans so tests don't leak
    for (const pid of pidsToCleanup) {
      killIfAlive(pid);
    }
    pidsToCleanup.length = 0;
  });

  it("process.exit(0) leaves orphaned children (demonstrates the bug)", async () => {
    const { childPid } = await runFixture("--mode=process-exit");
    pidsToCleanup.push(childPid);

    // The child should still be alive — this proves the bug
    expect(isProcessAlive(childPid)).toBe(true);
  });

  it("exitCode + cleanup kills children gracefully (the fix)", async () => {
    const { childPid, exitCode } = await runFixture("--mode=exitcode-cleanup");
    pidsToCleanup.push(childPid);

    expect(exitCode).toBe(0);
    const died = await waitForProcessDeath(childPid, 5000);
    expect(died).toBe(true);
  });

  it("SIGTERM handler kills children before exiting", async () => {
    const { proc, childPidPromise } = runFixtureLive("--mode=sigterm-cleanup");
    const childPid = await childPidPromise;
    pidsToCleanup.push(childPid);

    // Send SIGTERM to the parent
    proc.kill("SIGTERM");
    await waitForExit(proc);

    const died = await waitForProcessDeath(childPid, 5000);
    expect(died).toBe(true);
  });

  it("already-exited children don't cause errors during cleanup", async () => {
    const { childPid, exitCode, stderr } = await runFixture("--mode=quick-child");
    pidsToCleanup.push(childPid);

    expect(exitCode).toBe(0);
    // No unhandled errors in stderr
    expect(stderr).toBe("");
  });
});
