import { spawn as spawnCallback } from "cross-spawn";

const mode = process.argv[2] || "--mode=process-exit";

const activeChildren = new Set();

function killActiveChildren() {
  for (const child of activeChildren) {
    try { child.kill("SIGTERM"); } catch (e) {}
  }
  activeChildren.clear();
}

const sleepDuration = mode === "--mode=quick-child" ? "0" : "600";
const child = spawnCallback("sleep", [sleepDuration], { stdio: "ignore" });
activeChildren.add(child);
child.once("exit", () => activeChildren.delete(child));

// Tell the test harness the child's PID
process.stdout.write(JSON.stringify({ childPid: child.pid }) + "\n");

if (mode === "--mode=process-exit") {
  // Current broken behavior: exit immediately, orphaning children
  process.exit(0);
} else if (mode === "--mode=exitcode-cleanup") {
  // The fix: kill children before exiting
  killActiveChildren();
  process.exit(0);
} else if (mode === "--mode=sigterm-cleanup") {
  // Signal handler test: stay alive, handle SIGTERM gracefully
  process.on("SIGTERM", () => {
    killActiveChildren();
    process.exit(143);
  });
  // Keep alive until signaled
  setInterval(() => {}, 60000);
} else if (mode === "--mode=quick-child") {
  // Child exits immediately (sleep 0); used to test cleanup doesn't error
  // Wait a moment for child to exit, then call cleanup
  setTimeout(() => {
    killActiveChildren(); // should not throw
    process.exitCode = 0;
  }, 200);
}
