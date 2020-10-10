const {
  elmPagesCliFile,
  elmPagesUiFile,
} = require("../generator/src/elm-file-constants.js");
const generateRecords = require("../generator/src/generate-records.js");

test("one-page app", async () => {
  process.chdir(__dirname);
  const result = await doThing();
  console.log("result is", result);
  expect(result).toMatchSnapshot();
});

async function doThing() {
  const fs = require("fs");
  const path = require("path");
  XMLHttpRequest = require("xhr2");

  const DIR_PATH = path.join(process.cwd(), "../examples/simple/");
  const OUTPUT_FILE_NAME = "elm.js";

  const ELM_FILE_PATH = path.join(
    DIR_PATH,
    "./elm-stuff/elm-pages",
    OUTPUT_FILE_NAME
  );
  const util = require("util");
  const exec = util.promisify(require("child_process").exec);

  const output = await exec(
    "cd ../examples/simple/elm-stuff/elm-pages && elm-optimize-level-2 ../../src/Main.elm --output elm.js"
  );
  console.log("shell", `${output.stdout}`);

  const elmFileContent = fs.readFileSync(ELM_FILE_PATH, "utf-8");
  fs.writeFileSync(
    ELM_FILE_PATH,
    elmFileContent.replace(
      /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
      "return x"
    )
  );

  function runElmApp() {
    return new Promise((resolve, _) => {
      const mode /** @type { "dev" | "prod" } */ = "elm-to-html-beta";
      const staticHttpCache = {};
      const app = require(ELM_FILE_PATH).Elm.Main.init({
        flags: { secrets: process.env, mode, staticHttpCache },
      });

      app.ports.toJsPort.subscribe((
        /** @type { { head: SeoTag[], allRoutes: string[], html: string } }  */ fromElm
      ) => {
        if (fromElm.html) {
          console.log("@@@ fromElm", fromElm);
          resolve(fromElm.html);
        } else {
          console.log("??? fromElm", fromElm);
        }
      });
    });
  }
  return await runElmApp();
}
