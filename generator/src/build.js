const fs = require("./dir-helpers.js");
const path = require("path");
const spawnCallback = require("cross-spawn").spawn;
const codegen = require("./codegen.js");
const terser = require("terser");
const matter = require("gray-matter");
const globby = require("globby");
const preRenderHtml = require("./pre-render-html.js");
const { StaticPool } = require("node-worker-threads-pool");
const os = require("os");

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
  await fs.tryMkdir(`dist`);
}

async function run(options) {
  await ensureRequiredDirs();
  XMLHttpRequest = require("xhr2");

  const generateCode = codegen.generate();

  const copyDone = copyAssets();
  await generateCode;
  const cliDone = runCli(options);
  const compileClientDone = compileElm(options);

  await Promise.all([copyDone, cliDone, compileClientDone]);
}

async function runCli(options) {
  await compileCliApp(options);
  // runElmApp();
  const cpuCount = os.cpus().length;
  console.log("Threads: ", cpuCount);

  const pool = new StaticPool({
    size: Math.max(1, cpuCount / 2 - 1),
    task: path.join(__dirname, "./render-worker.js"),
  });

  let pages = JSON.parse(await pool.exec("/all-paths.json"));
  await Promise.allSettled(
    pages.map(async (/** @type {string} */ page) => {
      await pool.exec(page);
    })
  );
  pool.destroy();
}

function runElmApp() {
  process.on("beforeExit", (code) => {
    if (foundErrors) {
      process.exitCode = 1;
    } else {
    }
  });

  return new Promise((resolve, _) => {
    const mode /** @type { "dev" | "prod" } */ = "elm-to-html-beta";
    const staticHttpCache = {};
    const app = require(ELM_FILE_PATH).Elm.TemplateModulesBeta.init({
      flags: { secrets: process.env, mode, staticHttpCache },
    });

    app.ports.toJsPort.subscribe(async (/** @type { FromElm }  */ fromElm) => {
      // console.log({ fromElm });
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "InitialData") {
        generateFiles(fromElm.args[0].filesToGenerate);
      } else if (fromElm.tag === "PageProgress") {
        outputString(fromElm);
      } else if (fromElm.tag === "ReadFile") {
        const filePath = fromElm.args[0];
        try {
          const fileContents = (await fs.readFile(filePath)).toString();
          const parsedFile = matter(fileContents);
          app.ports.fromJsPort.send({
            tag: "GotFile",
            data: {
              filePath,
              parsedFrontmatter: parsedFile.data,
              withoutFrontmatter: parsedFile.content,
              rawFile: fileContents,
              jsonFile: jsonOrNull(fileContents),
            },
          });
        } catch (error) {
          app.ports.fromJsPort.send({
            tag: "BuildError",
            data: { filePath },
          });
        }
      } else if (fromElm.tag === "Glob") {
        const globPattern = fromElm.args[0];
        const matchedPaths = await globby(globPattern);

        app.ports.fromJsPort.send({
          tag: "GotGlob",
          data: { pattern: globPattern, result: matchedPaths },
        });
      } else if (fromElm.tag === "Errors") {
        console.error(fromElm.args[0].errorString);
        foundErrors = true;
      } else {
        console.log(fromElm);
        throw "Unknown port tag.";
      }
    });
  });
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

/**
 * @param {string} route
 */
function cleanRoute(route) {
  return route.replace(/(^\/|\/$)/, "");
}

/**
 * @param {string} cleanedRoute
 */
function pathToRoot(cleanedRoute) {
  return cleanedRoute === ""
    ? cleanedRoute
    : cleanedRoute
        .split("/")
        .map((_) => "..")
        .join("/")
        .replace(/\.$/, "./");
}

/**
 * @param {string} route
 */
function baseRoute(route) {
  const cleanedRoute = cleanRoute(route);
  return cleanedRoute === "" ? "./" : pathToRoot(route);
}

async function outputString(/** @type { PageProgress } */ fromElm) {
  const args = fromElm.args[0];
  console.log(`Pre-rendered /${args.route}`);
  const normalizedRoute = args.route.replace(/index$/, "");
  // await fs.mkdir(`./dist/${normalizedRoute}`, { recursive: true });
  await fs.tryMkdir(`./dist/${normalizedRoute}`);
  const contentJsonString = JSON.stringify({
    is404: args.is404,
    staticData: args.contentJson,
  });
  fs.writeFile(
    `dist/${normalizedRoute}/index.html`,
    preRenderHtml(args, contentJsonString, false)
  );
  fs.writeFile(`dist/${normalizedRoute}/content.json`, contentJsonString);
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

/**
 * @param {string} string
 */
function jsonOrNull(string) {
  try {
    return JSON.parse(string);
  } catch (e) {
    return { invalidJson: e.toString() };
  }
}
