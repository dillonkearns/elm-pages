/**
 * Dev command - starts a development server.
 */

import * as dev from "../dev-server.js";
import { normalizeUrl } from "./shared.js";

export async function run(options) {
  options.base = normalizeUrl(options.base);
  await dev.start(options);
}
