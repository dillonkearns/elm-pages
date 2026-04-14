import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Disable file-level parallelism. Several test files spawn lamdera/elm
    // compiler processes that share the global ~/.elm package cache. Running
    // them concurrently corrupts artifacts.x.dat files, causing flaky
    // "Corrupt File: not enough bytes" failures.
    fileParallelism: false,
  },
});
