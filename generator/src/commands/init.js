/**
 * Init command - scaffolds a new elm-pages project.
 */

import * as init from "../init.js";

export async function run(projectName) {
  await init.run(projectName);
}
