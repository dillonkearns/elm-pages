/**
 * Docs command - opens documentation for locally generated modules.
 */

import * as codegen from "../codegen.js";
import { default as DocServer } from "elm-doc-preview";

export async function run(options) {
  await codegen.generate("/");
  const server = new DocServer({
    port: options.port,
    browser: true,
    dir: "./elm-stuff/elm-pages/",
  });

  server.listen();
}
