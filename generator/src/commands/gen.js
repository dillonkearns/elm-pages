/**
 * Gen command - generates code without running a full build.
 */

import * as codegen from "../codegen.js";

export async function run(options) {
  await codegen.generate(options.base);
}
