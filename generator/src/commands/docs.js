/**
 * Docs command - opens documentation for locally generated modules.
 */

import * as codegen from "../codegen.js";
import { default as DocServer } from "elm-doc-preview";

/**
 * @param {{port: number}} options
 */
export async function run(options) {
  await codegen.generate("/");
  const server = new DocServer(
    /** @type {ConstructorParameters<typeof DocServer>[0]} */ (
      /** @satisfies {Partial<ConstructorParameters<typeof DocServer>[0]>} */ ({
        port: options.port,
        browser: true,
        dir: "./elm-stuff/elm-pages/",
      })
    )
  );

  server.listen();
}
