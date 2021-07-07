const fs = require("./dir-helpers.js");
const path = require("path");
const spawnCallback = require("cross-spawn").spawn;
const codegen = require("./codegen.js");
const terser = require("terser");
const os = require("os");
const { Worker, SHARE_ENV } = require("worker_threads");
const { ensureDirSync } = require("./file-helpers.js");
let pool = [];

const DIR_PATH = path.join(process.cwd());
const OUTPUT_FILE_NAME = "elm.js";

let foundErrors = false;
process.on("unhandledRejection", (error) => {
  console.error(error);
  process.exitCode = 1;
});

const ELM_FILE_PATH = path.join(
  DIR_PATH,
  "./elm-stuff/elm-pages",
  OUTPUT_FILE_NAME
);

async function ensureRequiredDirs() {
  ensureDirSync(`dist`);
  ensureDirSync(path.join(process.cwd(), ".elm-pages", "http-response-cache"));
}

async function run(options) {
  await ensureRequiredDirs();
  // since init/update are never called in pre-renders, and DataSource.Http is called using undici
  // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)
  XMLHttpRequest = {};

  const generateCode = codegen.generate();

  const copyDone = copyAssets();
  await generateCode;
  const cliDone = runCli(options);
  const compileClientDone = compileElm(options);

  await Promise.all([copyDone, cliDone, compileClientDone]);
}

function initWorker() {
  return new Promise((resolve, reject) => {
    let newWorker = {
      worker: new Worker(path.join(__dirname, "./render-worker.js"), {
        env: SHARE_ENV,
      }),
      ready: false,
    };
    newWorker.worker.once("online", () => {
      console.log(`${newWorker.worker.threadId} ready`);
      newWorker.ready = true;
      resolve(newWorker);
    });
  });
}

/**
 */
function prepareStaticPathsNew(thread) {
  return new Promise((resolve, reject) => {
    thread.ready = false;
    thread.worker.postMessage({
      mode: "build",
      tag: "render",
      pathname: "/all-paths.json",
    });
    thread.worker.once("message", (message) => {
      resolve(JSON.parse(message));
      thread.ready = true;
    });
  });
}

function delegateWork(pages) {
  pool
    .map((thread) => {
      return [thread, pages.pop()];
    })
    .forEach(async ([threadPromise, nextPage]) => {
      if (nextPage) {
        const thread = await threadPromise;
        thread.ready = false;
        thread.worker.postMessage({
          mode: "build",
          tag: "render",
          pathname: nextPage,
        });
        thread.worker.once("message", (message) => {
          cleanUp(thread);
          buildNextPage(thread, pages);
        });
        thread.worker.once("error", (error) => {
          console.error(error.context.errorString);
          process.exitCode = 1;
          cleanUp(thread);
          buildNextPage(thread, pages);
        });
      }
    });
}

function cleanUp(thread) {
  thread.worker.removeAllListeners("message");
  thread.worker.removeAllListeners("error");
  thread.ready = true;
}

function buildNextPage(thread, pages) {
  let nextPage = pages.pop();
  if (nextPage) {
    thread.ready = false;
    thread.worker.postMessage({
      mode: "build",
      tag: "render",
      pathname: nextPage,
    });
    thread.worker.once("message", (message) => {
      thread.ready = true;
      buildNextPage(thread, pages);
    });
    thread.worker.once("error", (error) => {
      console.error(error.context.errorString);
      process.exitCode = 1;
      cleanUp(thread);
      buildNextPage(thread, pages);
    });
  } else {
    console.log("@@@ DONE! NO NEXT PAGE!");
    thread.worker.terminate();
  }
}

async function runCli(options) {
  await compileCliApp(options);
  const cpuCount = os.cpus().length;
  console.log("Threads: ", cpuCount);

  const getPathsWorker = initWorker();
  const pagesPromise = getPathsWorker.then(prepareStaticPathsNew);
  const threadsToCreate = Math.max(1, cpuCount / 2 - 1);
  pool.push(getPathsWorker);
  for (let index = 0; index < threadsToCreate - 1; index++) {
    pool.push(initWorker());
  }
  const pages = await pagesPromise;
  delegateWork(pages);
}

/**
 * @param {{ path: string; content: string; }[]} filesToGenerate
 */
async function generateFiles(filesToGenerate) {
  filesToGenerate.forEach(async ({ path: pathToGenerate, content }) => {
    const fullPath = `dist/${pathToGenerate}`;
    console.log(`Generating file /${pathToGenerate}`);
    await fs.tryMkdir(path.dirname(fullPath));
    fs.writeFile(fullPath, content);
  });
}

async function compileElm(options) {
  const outputPath = `dist/elm.js`;
  const fullOutputPath = path.join(process.cwd(), `dist/elm.js`);
  await spawnElmMake(options, ".elm-pages/TemplateModulesBeta.elm", outputPath);

  if (!options.debug) {
    await runTerser(fullOutputPath);
  }
}

function spawnElmMake(options, elmEntrypointPath, outputPath, cwd) {
  return new Promise((resolve, reject) => {
    const fullOutputPath = cwd ? path.join(cwd, outputPath) : outputPath;
    if (fs.existsSync(fullOutputPath)) {
      fs.rmSync(fullOutputPath, {
        force: true /* ignore errors if file doesn't exist */,
      });
    }
    const subprocess = runElm(options, elmEntrypointPath, outputPath, cwd);

    subprocess.on("close", async (code) => {
      const fileOutputExists = await fs.exists(fullOutputPath);
      if (code == 0 && fileOutputExists) {
        resolve();
      } else {
        process.exitCode = 1;
        reject();
      }
    });
  });
}

/**
 * @param {string} elmEntrypointPath
 * @param {string} outputPath
 * @param {string} cwd
 */
function runElm(options, elmEntrypointPath, outputPath, cwd) {
  if (options.debug) {
    console.log("Running elm make");
    return spawnCallback(
      `elm`,
      ["make", elmEntrypointPath, "--output", outputPath, "--debug"],
      {
        // ignore stdout
        stdio: ["inherit", "ignore", "inherit"],
        cwd: cwd,
      }
    );
  } else {
    console.log("Running elm-optimize-level-2");
    return spawnCallback(
      `elm-optimize-level-2`,
      [elmEntrypointPath, "--output", outputPath],
      {
        // ignore stdout
        stdio: ["inherit", "ignore", "inherit"],
        cwd: cwd,
      }
    );
  }
}

/**
 * @param {string} filePath
 */
async function runTerser(filePath) {
  console.log("Running terser");
  const minifiedElm = await terser.minify(
    (await fs.readFile(filePath)).toString(),
    {
      ecma: 5,

      module: true,
      compress: {
        pure_funcs: [
          "F2",
          "F3",
          "F4",
          "F5",
          "F6",
          "F7",
          "F8",
          "F9",
          "A2",
          "A3",
          "A4",
          "A5",
          "A6",
          "A7",
          "A8",
          "A9",
        ],
        pure_getters: true,
        keep_fargs: false,
        unsafe_comps: true,
        unsafe: true,
        passes: 2,
      },
      mangle: true,
    }
  );
  if (minifiedElm.code) {
    await fs.writeFile(filePath, minifiedElm.code);
  } else {
    throw "Error running terser.";
  }
}

async function copyAssets() {
  fs.writeFile(
    "dist/elm-pages.js",
    fs.readFileSync(path.join(__dirname, "../static-code/elm-pages.js"))
  );
  fs.copyDirFlat("public", "dist");
}

async function compileCliApp(options) {
  await spawnElmMake(
    options,
    ".elm-pages/TemplateModulesBeta.elm",
    "elm.js",
    "./elm-stuff/elm-pages"
  );

  const elmFileContent = await fs.readFile(ELM_FILE_PATH, "utf-8");
  await fs.writeFile(
    ELM_FILE_PATH,
    elmFileContent
      .replace(
        /return \$elm\$json\$Json\$Encode\$string\(.REPLACE_ME_WITH_JSON_STRINGIFY.\)/g,
        "return " + (options.debug ? "_Json_wrap(x)" : "x")
      )
      .replace(
        "return ports ? { ports: ports } : {};",
        `const die = function() {
        managers = null
        model = null
        stepper = null
        ports = null
      }

      return ports ? { ports: ports, die: die } : { die: die };`
      )
  );
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; body: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

/** @typedef {     { body: string; head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */

/**
 * @param {Arg} fromElm
 * @param {string} contentJsonString
 * @returns {string}
 */

module.exports = { run };
