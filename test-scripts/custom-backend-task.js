// Capture threadId at module-load time in whatever thread loads us.
// In a Worker, this is that worker's threadId; in the main thread, 0.
import { threadId as myThreadId } from "node:worker_threads";

export async function environmentVariable(input) {
  input.mutable++;
  return "Done";
}

// End-to-end smoke tests for BackendTask.Custom.runBytes.
// echoBytes: returns the input unchanged, proving the wire is round-tripping.
export async function echoBytes(inputBytes) {
  return inputBytes;
}

// reverseBytes: returns the input reversed, proving JS can transform the payload.
export async function reverseBytes(inputBytes) {
  return Buffer.from(inputBytes).reverse();
}

// Worker port for BackendTask.Parallel.run end-to-end test.
// Treats input as a big-endian uint32, squares it, returns a 4-byte
// big-endian uint32. Includes a small CPU-bound spin so the
// main-thread-vs-worker difference is observable.
export async function squareU32(inputBytes) {
  if (inputBytes.length !== 4) {
    throw new Error(
      `squareU32 expected 4 bytes, got ${inputBytes.length}`
    );
  }
  const n = inputBytes.readUInt32BE(0);
  // Deliberate busy-wait to prove workers run concurrently.
  const deadline = Date.now() + 50;
  while (Date.now() < deadline) {
    // spin
  }
  const out = Buffer.alloc(4);
  out.writeUInt32BE((n * n) >>> 0, 0);
  return out;
}

// Worker port that reports its own threadId (proves tasks land on different workers).
// Busy-waits for 50ms so concurrent dispatches overlap, forcing the pool
// to pick different workers for concurrent tasks.
export async function reportThread(inputBytes) {
  const deadline = Date.now() + 50;
  while (Date.now() < deadline) {
    // spin
  }
  const buf = Buffer.alloc(4);
  buf.writeUInt32BE(myThreadId, 0);
  return buf;
}
