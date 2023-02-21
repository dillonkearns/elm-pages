#!/usr/bin/node

import * as fs from "node:fs";

const currentCompatibilityKey = 10;
const currentPackageVersion = JSON.parse(
  fs.readFileSync("./package.json")
).version;

fs.writeFileSync(
  "src/Pages/Internal/Platform/CompatibilityKey.elm",
  `module Pages.Internal.Platform.CompatibilityKey exposing (currentCompatibilityKey)


currentCompatibilityKey : Int
currentCompatibilityKey =
    ${currentCompatibilityKey}
`
);

fs.writeFileSync(
  "generator/src/compatibility-key.js",
  `export const compatibilityKey = ${currentCompatibilityKey};

export const packageVersion = "${currentPackageVersion}";
`
);

fs.writeFileSync(
  "./README.md",
  fs
    .readFileSync("./README.md")
    .toString()
    .replace(
      /Current Compatibility Key: \d+\./,
      `Current Compatibility Key: ${currentCompatibilityKey}.`
    )
);
