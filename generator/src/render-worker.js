import * as renderer from "../../generator/src/render.js";
import * as path from "node:path";
import * as fs from "./dir-helpers.js";
import { readFileSync, writeFileSync } from "node:fs";
import { parentPort, threadId, workerData } from "node:worker_threads";
import * as url from "node:url";
import { extractAndReplaceFrozenViews, replaceFrozenViewPlaceholders } from "./extract-frozen-views.js";
import { toExactBuffer } from "./binary-helpers.js";

async function run({ mode, pathname, serverRequest, portsFilePath }) {
  console.time(`${threadId} ${pathname}`);
  try {
    const renderResult = await renderer.render(
      typeof portsFilePath === "string"
        ? await import(url.pathToFileURL(path.resolve(portsFilePath)).href)
        : portsFilePath,
      workerData.basePath,
      await requireElm(mode),
      mode,
      pathname,
      serverRequest,
      function (patterns) {
        if (mode === "dev-server" && patterns.size > 0) {
          parentPort.postMessage({ tag: "watch", data: [...patterns] });
        }
      },
      true
    );

    if (mode === "dev-server") {
      parentPort.postMessage({ tag: "done", data: renderResult });
    } else if (mode === "build") {
      outputString(renderResult, pathname);
    } else {
      throw `Unknown mode ${mode}`;
    }
  } catch (error) {
    if (error.errorsJson) {
      parentPort.postMessage({ tag: "error", data: error.errorsJson });
    } else {
      parentPort.postMessage({ tag: "error", data: error });
    }
  }
  console.timeEnd(`${threadId} ${pathname}`);
}

async function requireElm(mode) {
  const compiledElmPath = path.join(
    process.cwd(),
    "elm-stuff/elm-pages/elm.cjs"
  );
  let pathAsUrl = url.pathToFileURL(compiledElmPath);
  const warnOriginal = console.warn;
  console.warn = function () {};
  const Elm = (await import(pathAsUrl.toString())).default;
  console.warn = warnOriginal;
  return Elm;
}

async function outputString(
  /** @type {Awaited<ReturnType<typeof renderer.render>> & {}} */ fromElm,
  /** @type string */ pathname
) {
  switch (fromElm.kind) {
    case "html": {
      const args = fromElm;
      const normalizedRoute = args.route.replace(/index$/, "");
      await fs.tryMkdir(`./dist/${normalizedRoute}`);
      const template = readFileSync("./dist/template.html", "utf8");

      // Extract frozen views from rendered HTML and replace __STATIC__ placeholders
      const { regions: frozenViews, html: updatedHtml } = extractAndReplaceFrozenViews(args.htmlString?.html || "");

      // Update the HTML with resolved frozen view IDs
      if (args.htmlString) {
        args.htmlString.html = updatedHtml;
      }

      if (args.contentDatPayload) {
        // Create combined format for content.dat (includes frozen views for SPA navigation)
        // Format: [4 bytes: frozen views JSON length (big-endian uint32)]
        //         [N bytes: frozen views JSON (UTF-8)]
        //         [remaining bytes: original ResponseSketch binary]
        const frozenViewsJson = JSON.stringify(frozenViews);
        const frozenViewsBuffer = Buffer.from(frozenViewsJson, 'utf8');
        const lengthBuffer = Buffer.alloc(4);
        lengthBuffer.writeUInt32BE(frozenViewsBuffer.length, 0);

        const contentDatBuffer = Buffer.concat([
          lengthBuffer,
          frozenViewsBuffer,
          toExactBuffer(args.contentDatPayload)
        ]);

        // Write the combined content.dat for SPA navigation
        writeFileSync(`dist/${normalizedRoute}/content.dat`, contentDatBuffer);

        // For bytesData embedded in HTML, use empty frozen views prefix
        // The decoder (skipFrozenViewsPrefix) expects this format even for initial load
        const emptyFrozenViews = {};
        const emptyFrozenViewsJson = JSON.stringify(emptyFrozenViews);
        const emptyFrozenViewsBuffer = Buffer.from(emptyFrozenViewsJson, 'utf8');
        const emptyLengthBuffer = Buffer.alloc(4);
        emptyLengthBuffer.writeUInt32BE(emptyFrozenViewsBuffer.length, 0);

        const htmlBytesBuffer = Buffer.concat([
          emptyLengthBuffer,
          emptyFrozenViewsBuffer,
          toExactBuffer(args.contentDatPayload)
        ]);

        // Update the bytesData in htmlString with the prefixed format
        args.htmlString.bytesData = htmlBytesBuffer.toString("base64");
      }

      writeFileSync(
        `dist/${normalizedRoute}/index.html`,
        renderTemplate(template, fromElm)
      );

      parentPort.postMessage({ tag: "done" });
      break;
    }
    case "api-response": {
      const body = fromElm.body.body;
      console.log(`Generated ${pathname}`);
      fs.writeFileSyncSafe(path.join("dist", pathname), body);
      if (pathname === "/all-paths.json") {
        parentPort.postMessage({ tag: "all-paths", data: body });
      } else {
        parentPort.postMessage({ tag: "done" });
      }

      break;
    }
  }
}

function renderTemplate(template, renderResult) {
  const info = renderResult.htmlString;
  return template
    .replace(
      /<!--\s*PLACEHOLDER_HEAD_AND_DATA\s*-->/,
      `${info.headTags}
                  <script id="__ELM_PAGES_BYTES_DATA__" type="application/octet-stream">${info.bytesData}</script>`
    )
    .replace(/<!--\s*PLACEHOLDER_TITLE\s*-->/, info.title)
    .replace(/<!--\s*PLACEHOLDER_HTML\s* -->/, info.html)
    .replace(/<!-- ROOT -->\S*<html lang="en">/m, info.rootElement);
}

parentPort.on("message", run);
