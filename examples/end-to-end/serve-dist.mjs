// A tiny static file server for the production build in ./dist, used by the
// production Cypress tests (cypress.production.config.js).
//
//   node serve-dist.mjs [port]

import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";

const dist = path.resolve("dist");
const port = Number(process.argv[2] || 3457);
const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".dat": "application/octet-stream",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
};

http
  .createServer((request, response) => {
    const urlPath = decodeURIComponent(
      new URL(request.url || "/", "http://localhost").pathname
    );
    let filePath = path.join(dist, urlPath);
    if (!filePath.startsWith(dist)) {
      response.writeHead(403).end();
      return;
    }
    if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
      filePath = path.join(filePath, "index.html");
    }
    if (!fs.existsSync(filePath)) {
      response.writeHead(404).end("Not found");
      return;
    }
    response.writeHead(200, {
      "Content-Type":
        contentTypes[path.extname(filePath)] || "application/octet-stream",
    });
    fs.createReadStream(filePath).pipe(response);
  })
  .listen(port, () => {
    console.log(`Serving ${dist} at http://localhost:${port}`);
  });
