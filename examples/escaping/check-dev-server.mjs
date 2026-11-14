// Checks that the dev server renders the same page body as `elm-pages build`.
//
// The dev server compiles the server-side code on its own path (and with
// `--optimize` unless `--debug` is passed), so it can break while the build
// still works. See https://github.com/dillonkearns/elm-pages/issues/622
//
// Run this after `elm-pages build`, so `dist/escaping/index.html` is the
// snapshot that `npm test` has just checked.

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as net from "node:net";

const snapshotPath = "dist/escaping/index.html";

/** Everything from the opening body tag on. The head differs between dev and build. */
function body(html) {
  const start = html.indexOf("<body");
  if (start === -1) {
    throw new Error(`No <body> found in:\n${html}`);
  }
  return html.slice(start);
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on("error", reject);
    server.listen(0, () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

async function fetchWhenReady(url, devServer) {
  const giveUpAt = Date.now() + 120_000;
  while (Date.now() < giveUpAt) {
    if (devServer.exitCode !== null) {
      throw new Error(`The dev server exited with code ${devServer.exitCode}`);
    }
    try {
      const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
      if (response.ok) {
        return await response.text();
      }
    } catch (error) {
      // Not listening yet, or too slow to answer; try again
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${url}`);
}

const port = await freePort();
const devServer = spawn("npx", ["elm-pages", "dev", "--port", String(port)], {
  stdio: ["ignore", "inherit", "inherit"],
});

let exitCode = 0;
try {
  const expected = body(fs.readFileSync(snapshotPath, "utf8")).split("\n");
  const actual = body(
    await fetchWhenReady(`http://localhost:${port}/escaping`, devServer)
  ).split("\n");

  const line = expected.findIndex((_, i) => expected[i] !== actual[i]);
  if (line !== -1 || expected.length !== actual.length) {
    const at = line === -1 ? expected.length : line;
    console.error(
      `The dev server's page body for /escaping is different from ${snapshotPath}.\n` +
        `First difference, on line ${at + 1} of the body:\n\n` +
        `build: ${expected[at]}\n\ndev:   ${actual[at]}\n`
    );
    exitCode = 1;
  } else {
    console.log(`The dev server's page body matches ${snapshotPath}`);
  }
} catch (error) {
  console.error(error);
  exitCode = 1;
} finally {
  devServer.kill();
}
process.exit(exitCode);
