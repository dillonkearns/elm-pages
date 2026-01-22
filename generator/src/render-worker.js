import * as renderer from "../../generator/src/render.js";
import * as path from "node:path";
import * as fs from "./dir-helpers.js";
import { readFileSync, writeFileSync } from "node:fs";
import { parentPort, threadId, workerData } from "node:worker_threads";
import * as url from "node:url";
import { extractAndReplaceStaticRegions, replaceStaticPlaceholders } from "./extract-static-regions.js";

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
  /** @type { { kind: 'page'; data: PageProgress } | { kind: 'api'; data: Object }  } */ fromElm,
  /** @type string */ pathname
) {
  switch (fromElm.kind) {
    case "html": {
      const args = fromElm;
      const normalizedRoute = args.route.replace(/index$/, "");
      await fs.tryMkdir(`./dist/${normalizedRoute}`);
      const template = readFileSync("./dist/template.html", "utf8");

      // Extract static regions from rendered HTML and replace __STATIC__ placeholders
      const { regions: staticRegions, html: updatedHtml } = extractAndReplaceStaticRegions(args.htmlString?.html || "");

      // Update the HTML with resolved static region IDs
      if (args.htmlString) {
        args.htmlString.html = updatedHtml;
      }

      if (args.contentDatPayload) {
        // Create combined format for content.dat (includes static regions for SPA navigation)
        // Format: [4 bytes: static regions JSON length (big-endian uint32)]
        //         [N bytes: static regions JSON (UTF-8)]
        //         [remaining bytes: original ResponseSketch binary]
        const staticRegionsJson = JSON.stringify(staticRegions);
        const staticRegionsBuffer = Buffer.from(staticRegionsJson, 'utf8');
        const lengthBuffer = Buffer.alloc(4);
        lengthBuffer.writeUInt32BE(staticRegionsBuffer.length, 0);

        const contentDatBuffer = Buffer.concat([
          lengthBuffer,
          staticRegionsBuffer,
          Buffer.from(args.contentDatPayload.buffer)
        ]);

        // Write the combined content.dat for SPA navigation
        writeFileSync(`dist/${normalizedRoute}/content.dat`, contentDatBuffer);

        // For bytesData embedded in HTML, use empty static regions (they're already in the DOM)
        const emptyStaticRegions = {};
        const emptyStaticRegionsJson = JSON.stringify(emptyStaticRegions);
        const emptyStaticRegionsBuffer = Buffer.from(emptyStaticRegionsJson, 'utf8');
        const emptyLengthBuffer = Buffer.alloc(4);
        emptyLengthBuffer.writeUInt32BE(emptyStaticRegionsBuffer.length, 0);

        const htmlBytesBuffer = Buffer.concat([
          emptyLengthBuffer,
          emptyStaticRegionsBuffer,
          Buffer.from(args.contentDatPayload.buffer)
        ]);

        // Update the bytesData in htmlString with empty static regions header
        args.htmlString.bytesData = htmlBytesBuffer.toString("base64");

        if (Object.keys(staticRegions).length > 0) {
          console.log(`  Included ${Object.keys(staticRegions).length} static region(s) in content.dat for ${normalizedRoute}`);
        }
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

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */
