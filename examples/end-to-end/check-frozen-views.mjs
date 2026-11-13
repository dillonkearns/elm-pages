// Checks a production build (`elm-pages build`) of this example to make sure
// frozen views (`View.freeze`) really were transformed:
//
// - the frozen content is in the pre-rendered HTML, marked for the browser
// - the code and data that only the frozen content needs are NOT in the
//   client bundle
// - a control text that is not frozen IS in the client bundle, which proves
//   we are looking in the right place
//
// The texts come from app/Route/StaticRegionTest.elm.
//
// Run it after a build:  node check-frozen-views.mjs

import * as fs from "node:fs";
import * as path from "node:path";

const dist = path.resolve("dist");
const frozenViewText =
  "Frozen view code: this text must not be in the client bundle.";
const frozenDataText =
  "Frozen data: this text must not be in the client bundle.";
const dynamicViewText =
  "Dynamic view code: this text must be in the client bundle.";

const html = fs.readFileSync(
  path.join(dist, "static-region-test/index.html"),
  "utf8"
);
const bundleFiles = fs
  .readdirSync(dist)
  .filter((file) => /^elm(\..+)?\.js$/.test(file));
const bundles = bundleFiles.map((file) => ({
  file,
  code: fs.readFileSync(path.join(dist, file), "utf8"),
}));

/** @type {string[]} */
const problems = [];

/**
 * @param {boolean} condition
 * @param {string} problem
 */
function check(condition, problem) {
  if (!condition) {
    problems.push(problem);
  }
}

const frozenRegion = /<div data-static="0"[^>]*>[\s\S]*<\/div>/.exec(html);
check(
  frozenRegion !== null,
  `The HTML has no element marked data-static="0". The server did not wrap the frozen view.`
);
for (const text of [frozenViewText, frozenDataText]) {
  check(
    (frozenRegion ? frozenRegion[0] : "").includes(text),
    `The frozen view in the HTML is missing: "${text}"`
  );
}
check(
  html.includes(dynamicViewText),
  `The HTML is missing the dynamic text: "${dynamicViewText}"`
);

check(bundleFiles.length > 0, `Found no client bundle (elm*.js) in ${dist}.`);
for (const { file, code } of bundles) {
  check(
    code.includes(dynamicViewText),
    `${file} is missing the dynamic text, so it is not the client bundle this check expects: "${dynamicViewText}"`
  );
  check(
    !code.includes(frozenViewText),
    `${file} contains frozen view code. View.freeze was not transformed for the client: "${frozenViewText}"`
  );
  check(
    !code.includes(frozenDataText),
    `${file} contains data that only a frozen view uses: "${frozenDataText}"`
  );
  check(
    code.includes("__ELM_PAGES_STATIC__0"),
    `${file} has no placeholder for the frozen view ("__ELM_PAGES_STATIC__0").`
  );
  check(
    code.includes("__ELM_PAGES_FROZEN_VIEWS__"),
    `${file} is missing the virtual DOM patch that draws frozen views.`
  );
}

if (problems.length > 0) {
  console.error("Frozen view check failed:\n");
  for (const problem of problems) {
    console.error(`  - ${problem}`);
  }
  process.exit(1);
}
console.log(
  `Frozen view check OK (${bundleFiles.join(", ")}: frozen code and data left out, dynamic code kept).`
);
