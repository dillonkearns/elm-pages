import * as fs from "node:fs";
import * as fsExtra from "fs-extra";
import { rewriteElmJson } from "./rewrite-elm-json.js";
import { rewriteClientElmJson } from "./rewrite-client-elm-json.js";
import { elmPagesCliFile, elmPagesUiFile } from "./elm-file-constants.js";
import { spawn as spawnCallback } from "cross-spawn";
import { default as which } from "which";
import { generateTemplateModuleConnector } from "./generate-template-module-connector.js";

import * as path from "path";
import { ensureDirSync, deleteIfExists } from "./file-helpers.js";
import { fileURLToPath } from "url";
global.builtAt = new Date();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * @param {string} basePath
 */
export async function generate(basePath) {
  const cliCode = await generateTemplateModuleConnector(basePath, "cli");
  const browserCode = await generateTemplateModuleConnector(
    basePath,
    "browser"
  );
  ensureDirSync("./elm-stuff");
  ensureDirSync("./.elm-pages");
  ensureDirSync("./gen");
  ensureDirSync("./elm-stuff/elm-pages/.elm-pages");

  const uiFileContent = elmPagesUiFile();

  await Promise.all([
    copyToBoth("RouteBuilder.elm"),
    copyToBoth("SharedTemplate.elm"),
    copyToBoth("SiteConfig.elm"),

    fs.promises.writeFile("./.elm-pages/Pages.elm", uiFileContent),
    fs.promises.copyFile(
      path.join(__dirname, `./elm-application.json`),
      `./elm-stuff/elm-pages/elm-application.json`
    ),
    // write `Pages.elm` with cli interface
    fs.promises.writeFile(
      "./elm-stuff/elm-pages/.elm-pages/Pages.elm",
      elmPagesCliFile()
    ),
    fs.promises.writeFile(
      "./elm-stuff/elm-pages/.elm-pages/Main.elm",
      cliCode.mainModule
    ),
    fs.promises.writeFile(
      "./elm-stuff/elm-pages/.elm-pages/Route.elm",
      cliCode.routesModule
    ),
    fs.promises.writeFile("./.elm-pages/Main.elm", browserCode.mainModule),
    fs.promises.writeFile("./.elm-pages/Route.elm", browserCode.routesModule),
    writeFetcherModules("./.elm-pages", browserCode.fetcherModules),
    writeFetcherModules(
      "./elm-stuff/elm-pages/client/.elm-pages",
      browserCode.fetcherModules
    ),
    writeFetcherModules(
      "./elm-stuff/elm-pages/.elm-pages",
      browserCode.fetcherModules
    ),
    // write modified elm.json to elm-stuff/elm-pages/
    rewriteElmJson("./elm.json", "./elm-stuff/elm-pages/elm.json"),
    // ...(await listFiles("./Pages/Internal")).map(copyToBoth),
  ]);
}

function writeFetcherModules(basePath, fetcherData) {
  Promise.all(
    fetcherData.map(([name, fileContent]) => {
      let filePath = path.join(basePath, `/Fetcher/${name.join("/")}.elm`);
      ensureDirSync(path.dirname(filePath));
      return fs.promises.writeFile(filePath, fileContent);
    })
  );
}

async function newCopyBoth(modulePath) {
  await fs.promises.copyFile(
    path.join(__dirname, modulePath),
    path.join(`./elm-stuff/elm-pages/client/.elm-pages/`, modulePath)
  );
}

export async function generateClientFolder(basePath) {
  const browserCode = await generateTemplateModuleConnector(
    basePath,
    "browser"
  );
  const uiFileContent = elmPagesUiFile();
  ensureDirSync("./elm-stuff/elm-pages/client/app");
  ensureDirSync("./elm-stuff/elm-pages/client/.elm-pages");
  await newCopyBoth("RouteBuilder.elm");
  await newCopyBoth("SharedTemplate.elm");
  await newCopyBoth("SiteConfig.elm");

  await rewriteClientElmJson();
  await fsExtra.copy("./app", "./elm-stuff/elm-pages/client/app", {
    recursive: true,
  });

  await fs.promises.writeFile(
    "./elm-stuff/elm-pages/client/.elm-pages/Main.elm",
    browserCode.mainModule
  );
  await fs.promises.writeFile(
    "./elm-stuff/elm-pages/client/.elm-pages/Route.elm",
    browserCode.routesModule
  );
  await fs.promises.writeFile(
    "./elm-stuff/elm-pages/client/.elm-pages/Pages.elm",
    uiFileContent
  );
  await runElmReviewCodemod("./elm-stuff/elm-pages/client/");
}

/**
 * @param {string} [ cwd ]
 */
async function runElmReviewCodemod(cwd) {
  return new Promise(async (resolve, reject) => {
    const child = spawnCallback(
      `elm-review`,
      [
        "--fix-all-without-prompt",
        "--report",
        "json",
        "--namespace",
        "elm-pages",
        "--config",
        path.join(__dirname, "../../generator/dead-code-review"),
        "--elmjson",
        "elm.json",
        "--compiler",
        await which("lamdera"),
      ],
      { cwd: path.join(process.cwd(), cwd || ".") }
    );

    let scriptOutput = "";

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", function (/** @type {string} */ data) {
      scriptOutput += data.toString();
    });
    child.on("error", function () {
      reject(scriptOutput);
    });

    child.on("close", function (code) {
      if (code === 0) {
        resolve(scriptOutput);
      } else {
        reject(scriptOutput);
      }
    });
  });
}

/**
 * @param {string} moduleToCopy
 * @returns { Promise<void> }
 */
async function copyToBoth(moduleToCopy) {
  await Promise.all([
    copyFileEnsureDir(
      path.join(__dirname, moduleToCopy),
      path.join(`./.elm-pages/`, moduleToCopy)
    ),
    copyFileEnsureDir(
      path.join(__dirname, moduleToCopy),
      path.join(`./elm-stuff/elm-pages/client/.elm-pages`, moduleToCopy)
    ),
    copyFileEnsureDir(
      path.join(__dirname, moduleToCopy),
      path.join(`./elm-stuff/elm-pages/.elm-pages/`, moduleToCopy)
    ),
  ]);
}

/**
 * @param {string} from
 * @param {string} to
 */
async function copyFileEnsureDir(from, to) {
  await fs.promises.mkdir(path.dirname(to), {
    recursive: true,
  });
  await fs.promises.copyFile(from, to);
}

/**
 * @param {string} dir
 * @returns {Promise<string[]>}
 */
async function listFiles(dir) {
  try {
    const fullDir = path.join(__dirname, dir);
    const files = await fs.promises.readdir(fullDir);
    return merge(
      await Promise.all(
        files.flatMap(async (file_) => {
          const file = path.join(dir, path.basename(file_));
          if (
            (await fs.promises.stat(path.join(__dirname, file))).isDirectory()
          ) {
            return await listFiles(file);
          } else {
            return [file];
          }
        })
      )
    );
  } catch (e) {
    return [];
  }
}

/**
 * @param {any[]} arrays
 */
function merge(arrays) {
  return [].concat.apply([], arrays);
}
