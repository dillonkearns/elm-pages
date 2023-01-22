import * as seo from "./seo-renderer.js";
import * as packageJson from "../../package.json" assert { type: "json" };
import * as path from "path";
import { fileURLToPath } from "url";

const cliVersion = packageJson.version;

/** @typedef { { head: any[]; errors: any[]; html: string; route: string; title: string; } } Arg */
/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

export function wrapHtml(basePath, fromElm, contentDatPayload) {
  const seoData = seo.gather(fromElm.head);
  return {
    kind: "html-template",
    title: fromElm.title,
    html: fromElm.html,
    bytesData: Buffer.from(contentDatPayload.buffer).toString("base64"),
    headTags: seoData.headTags,
    rootElement: seoData.rootElement,
  };
}

/**
 * @param {boolean} devMode
 * @param {(context: {cliVersion: string;}) => string} userHeadTagsTemplate
 */
export function templateHtml(devMode, userHeadTagsTemplate) {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  return /* html */ `<!DOCTYPE html>
<!-- ROOT --><html lang="en">
  <head>
    <meta charset="UTF-8" />
    <title><!-- PLACEHOLDER_TITLE --></title>
    ${
      devMode
        ? `<script src="/hmr.js" type="text/javascript"></script>
    <link rel="stylesheet" href="/dev-style.css">`
        : `<!-- PLACEHOLDER_PRELOADS -->`
    }
    <script defer src="/elm.js" type="text/javascript"></script>
    ${
      devMode
        ? `<script src="/elm-pages.js" type="module"></script>`
        : `<script defer src="${path.join(
            __dirname,
            "../static-code/elm-pages.js"
          )}" type="module"></script>`
    }
    ${indent(userHeadTagsTemplate({ cliVersion }))}
    <!-- PLACEHOLDER_HEAD_AND_DATA -->
  </head>
  <body>
    <div data-url="" display="none"></div>
    <!-- PLACEHOLDER_HTML -->
  </body>
</html>`;
}

/**
 * @param {string} snippet
 */
function indent(snippet) {
  return snippet
    .split("\n")
    .map((line) => `    ${line}`)
    .join("\n");
}

/**
 * @param {string} processedTemplate
 */
export function replaceTemplate(processedTemplate, info) {
  return processedTemplate
    .replace(
      /<!--\s*PLACEHOLDER_HEAD_AND_DATA\s*-->/,
      `${info.headTags}
                  <script id="__ELM_PAGES_BYTES_DATA__" type="application/octet-stream">${info.bytesData}</script>`
    )
    .replace(/<!--\s*PLACEHOLDER_TITLE\s*-->/, info.title)
    .replace(/<!--\s*PLACEHOLDER_HTML\s* -->/, info.html)
    .replace(/<!-- ROOT -->\S*<html lang="en">/m, info.rootElement);
}
