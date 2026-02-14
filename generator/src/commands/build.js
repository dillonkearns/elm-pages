/**
 * Build command - runs a full site build.
 */

import * as build from "../build.js";
import { normalizeUrl } from "./shared.js";

export async function run(options) {
  options.base = normalizeUrl(options.base);
  await build.run(options);
}
