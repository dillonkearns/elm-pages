// @ts-check

import * as path from "node:path";
import { default as mm } from "micromatch";
import { default as matter } from "gray-matter";
import * as globby from "globby";
import * as fsPromises from "node:fs/promises";
import * as preRenderHtml from "./pre-render-html.js";
import { lookupOrPerform } from "./request-cache.js";
import * as kleur from "kleur/colors";
import * as cookie from "cookie-signature";
import { compatibilityKey } from "./compatibility-key.js";
import * as fs from "node:fs";
import * as crypto from "node:crypto";
import { restoreColorSafe } from "./error-formatter.js";
import { Spinnies } from "./spinnies/index.js";
import { default as which } from "which";
import * as readline from "readline";
import { spawn as spawnCallback } from "cross-spawn";
import * as consumers from "stream/consumers";
import * as zlib from "node:zlib";
import { Readable } from "node:stream";
import * as validateStream from "./validate-stream.js";
import { default as makeFetchHappenOriginal } from "make-fetch-happen";

let verbosity = 2;
const spinnies = new Spinnies();

process.on("unhandledRejection", (error) => {
  console.error(error);
});
let foundErrors;

/**
 *
 * @param {string} basePath
 * @param {Object} elmModule
 * @param {string} path
 * @param {{ method: string; hostname: string; query: Record<string, string | undefined>; headers: Record<string, string>; host: string; pathname: string; port: number | null; protocol: string; rawUrl: string; }} request
 * @param {(pattern: string) => void} addBackendTaskWatcher
 * @param {boolean} hasFsAccess
 * @returns
 */
export async function render(
  portsFile,
  basePath,
  elmModule,
  mode,
  path,
  request,
  addBackendTaskWatcher,
  hasFsAccess
) {
  // const { fs, resetInMemoryFs } = require("./request-cache-fs.js")(hasFsAccess);
  // resetInMemoryFs();
  foundErrors = false;
  // since init/update are never called in pre-renders, and BackendTask.Http is called using pure NodeJS HTTP fetching
  // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)
  global.XMLHttpRequest = {};
  const result = await runElmApp(
    portsFile,
    basePath,
    elmModule,
    mode,
    path,
    request,
    addBackendTaskWatcher,
    hasFsAccess
  );
  return result;
}

/**
 * @param {Object} elmModule
 * @returns
 * @param {string[]} cliOptions
 * @param {any} portsFile
 * @param {string} scriptModuleName
 */
export async function runGenerator(
  cliOptions,
  portsFile,
  elmModule,
  scriptModuleName
) {
  global.isRunningGenerator = true;
  // const { fs, resetInMemoryFs } = require("./request-cache-fs.js")(true);
  // resetInMemoryFs();
  foundErrors = false;
  // since init/update are never called in pre-renders, and BackendTask.Http is called using pure NodeJS HTTP fetching
  // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)
  global.XMLHttpRequest = {};
  try {
    const result = await runGeneratorAppHelp(
      cliOptions,
      portsFile,
      "",
      elmModule,
      scriptModuleName,
      "production",
      "",
      true
    );
    return result;
  } catch (error) {
    process.exitCode = 1;
    console.log(restoreColorSafe(error));
  }
}
/**
 * @param {string} basePath
 * @param {Object} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @returns {Promise<({is404: boolean;} & ({kind: 'json';contentJson: string;} | {kind: 'html';htmlString: string;} | {kind: 'api-response';body: string;}))>}
 * @param {string[]} cliOptions
 * @param {any} portsFile
 * @param {typeof import("fs") | import("memfs").IFs} fs
 * @param {boolean} hasFsAccess
 * @param {string} scriptModuleName
 */
function runGeneratorAppHelp(
  cliOptions,
  portsFile,
  basePath,
  elmModule,
  scriptModuleName,
  mode,
  pagePath,
  hasFsAccess
) {
  const isDevServer = mode !== "build";
  let patternsToWatch = new Set();
  let app = null;
  let killApp;
  return new Promise((resolve, reject) => {
    const isBytes = pagePath.match(/content\.dat\/?$/);

    app = elmModule.Elm.ScriptMain.init({
      flags: {
        compatibilityKey,
        argv: ["", `elm-pages run ${scriptModuleName}`, ...cliOptions],
        versionMessage: "1.2.3",
      },
    });

    killApp = () => {
      app.ports.toJsPort.unsubscribe(portHandler);
      app.die();
      app = null;
      // delete require.cache[require.resolve(compiledElmPath)];
    };

    async function portHandler(/** @type { FromElm }  */ newThing) {
      let fromElm;
      let contentDatPayload;

      fromElm = newThing;
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "ApiResponse") {
        // Finished successfully
        process.exit(0);
      } else if (fromElm.tag === "PageProgress") {
        const args = fromElm.args[0];

        if (isBytes) {
          resolve({
            kind: "bytes",
            is404: false,
            contentJson: JSON.stringify({
              staticData: args.contentJson,
              is404: false,
            }),
            statusCode: args.statusCode,
            headers: args.headers,
            contentDatPayload,
          });
        } else {
          resolve(
            outputString(basePath, fromElm, isDevServer, contentDatPayload)
          );
        }
      } else if (fromElm.tag === "DoHttp") {
        app.ports.gotBatchSub.send(
          Object.fromEntries(
            await Promise.all(
              fromElm.args[0].map(([requestHash, requestToPerform]) => {
                if (
                  requestToPerform.url !== "elm-pages-internal://port" &&
                  requestToPerform.url.startsWith("elm-pages-internal://")
                ) {
                  return runInternalJob(
                    requestHash,
                    app,
                    mode,
                    requestToPerform,
                    hasFsAccess,
                    patternsToWatch,
                    portsFile
                  );
                } else {
                  return runHttpJob(
                    requestHash,
                    portsFile,
                    app,
                    mode,
                    requestToPerform,
                    hasFsAccess,
                    requestToPerform
                  );
                }
              })
            )
          )
        );
      } else if (fromElm.tag === "Errors") {
        foundErrors = true;
        spinnies.stopAll();
        reject(fromElm.args[0].errorsJson);
      } else {
        console.log(fromElm);
      }
    }
    app.ports.toJsPort.subscribe(portHandler);
  }).finally(() => {
    try {
      killApp();
      killApp = null;
    } catch (error) {}
  });
}

/**
 * @param {string} basePath
 * @param {Object} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @param {{ method: string; hostname: string; query: string; headers: Object; host: string; pathname: string; port: string; protocol: string; rawUrl: string; }} request
 * @param {(pattern: string) => void} addBackendTaskWatcher
 * @returns {Promise<({is404: boolean} & ( { kind: 'json'; contentJson: string} | { kind: 'html'; htmlString: string } | { kind: 'api-response'; body: string; }) )>}
 */
function runElmApp(
  portsFile,
  basePath,
  elmModule,
  mode,
  pagePath,
  request,
  addBackendTaskWatcher,
  hasFsAccess
) {
  const isDevServer = mode !== "build";
  let patternsToWatch = new Set();
  let app = null;
  let killApp;
  return new Promise((resolve, reject) => {
    const isBytes = pagePath.match(/content\.dat\/?$/);
    const route = pagePath
      .replace(/content\.json\/?$/, "")
      .replace(/content\.dat\/?$/, "");

    const modifiedRequest = { ...request, path: route };
    app = elmModule.Elm.Main.init({
      flags: {
        mode,
        compatibilityKey,
        request: {
          payload: modifiedRequest,
          kind: "single-page",
          jsonOnly: !!isBytes,
        },
      },
    });

    killApp = () => {
      app.ports.toJsPort.unsubscribe(portHandler);
      app.ports.sendPageData.unsubscribe(portHandler);
      app.die();
      app = null;
      // delete require.cache[require.resolve(compiledElmPath)];
    };

    async function portHandler(/** @type { FromElm }  */ newThing) {
      let fromElm;
      let contentDatPayload;
      if ("oldThing" in newThing) {
        fromElm = newThing.oldThing;
        contentDatPayload = newThing.binaryPageData;
      } else {
        fromElm = newThing;
      }
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "ApiResponse") {
        const args = fromElm.args[0];

        resolve({
          kind: "api-response",
          is404: args.is404,
          statusCode: args.statusCode,
          body: args.body,
        });
      } else if (fromElm.tag === "PageProgress") {
        const args = fromElm.args[0];
        if (isBytes) {
          resolve({
            kind: "bytes",
            is404: false,
            contentJson: JSON.stringify({
              staticData: args.contentJson,
              is404: false,
            }),
            statusCode: args.statusCode,
            headers: args.headers,
            contentDatPayload,
          });
        } else {
          resolve(
            outputString(basePath, fromElm, isDevServer, contentDatPayload)
          );
        }
      } else if (fromElm.tag === "DoHttp") {
        app.ports.gotBatchSub.send(
          Object.fromEntries(
            await Promise.all(
              fromElm.args[0].map(([requestHash, requestToPerform]) => {
                if (
                  requestToPerform.url !== "elm-pages-internal://port" &&
                  requestToPerform.url.startsWith("elm-pages-internal://")
                ) {
                  return runInternalJob(
                    requestHash,
                    app,
                    mode,
                    requestToPerform,
                    hasFsAccess,
                    patternsToWatch,
                    portsFile
                  );
                } else {
                  return runHttpJob(
                    requestHash,
                    portsFile,
                    app,
                    mode,
                    requestToPerform,
                    hasFsAccess,
                    requestToPerform
                  );
                }
              })
            )
          )
        );
      } else if (fromElm.tag === "Errors") {
        foundErrors = true;
        spinnies.stopAll();
        reject(fromElm.args[0].errorsJson);
      } else {
        console.log(fromElm);
      }
    }
    app.ports.toJsPort.subscribe(portHandler);
    app.ports.sendPageData.subscribe(portHandler);
  }).finally(() => {
    addBackendTaskWatcher(patternsToWatch);
    try {
      killApp();
      killApp = null;
    } catch (error) {}
  });
}
/**
 * @param {string} basePath
 * @param {PageProgress} fromElm
 * @param {boolean} isDevServer
 */
async function outputString(
  basePath,
  /** @type { PageProgress } */ fromElm,
  isDevServer,
  contentDatPayload
) {
  const args = fromElm.args[0];
  let contentJson = {};
  contentJson["staticData"] = args.contentJson;
  contentJson["is404"] = args.is404;
  contentJson["path"] = args.route;
  contentJson["statusCode"] = args.statusCode;
  contentJson["headers"] = args.headers;
  const normalizedRoute = args.route.replace(/index$/, "");

  return {
    is404: args.is404,
    route: normalizedRoute,
    htmlString: preRenderHtml.wrapHtml(basePath, args, contentDatPayload),
    contentJson: args.contentJson,
    statusCode: args.statusCode,
    headers: args.headers,
    kind: "html",
    contentDatPayload,
  };
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */

/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

/** @typedef { { head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */

async function runHttpJob(
  requestHash,
  portsFile,
  app,
  mode,
  requestToPerform,
  hasFsAccess,
  useCache
) {
  try {
    const lookupResponse = await lookupOrPerform(
      portsFile,
      mode,
      requestToPerform,
      hasFsAccess,
      useCache
    );

    if (lookupResponse.kind === "cache-response-path") {
      const responseFilePath = lookupResponse.value;
      return [
        requestHash,
        {
          request: requestToPerform,
          response: JSON.parse(
            (await fs.promises.readFile(responseFilePath, "utf8")).toString()
          ),
        },
      ];
    } else if (lookupResponse.kind === "response-json") {
      return [
        requestHash,
        {
          request: requestToPerform,
          response: lookupResponse.value,
        },
      ];
    } else {
      throw `Unexpected kind ${lookupResponse}`;
    }
  } catch (error) {
    console.log("@@@ERROR", error);
    // sendError(app, error);
  }
}

function stringResponse(request, string) {
  return {
    request,
    response: { bodyKind: "string", body: string },
  };
}
function jsonResponse(request, json) {
  return {
    request,
    response: { bodyKind: "json", body: json },
  };
}

async function runInternalJob(
  requestHash,
  app,
  mode,
  requestToPerform,
  hasFsAccess,
  patternsToWatch,
  portsFile
) {
  try {
    if (requestToPerform.url === "elm-pages-internal://log") {
      return [requestHash, await runLogJob(requestToPerform)];
    } else if (requestToPerform.url === "elm-pages-internal://read-file") {
      return [
        requestHash,
        await readFileJobNew(requestToPerform, patternsToWatch),
      ];
    } else if (requestToPerform.url === "elm-pages-internal://glob") {
      return [requestHash, await runGlobNew(requestToPerform, patternsToWatch)];
    } else if (requestToPerform.url === "elm-pages-internal://randomSeed") {
      return [
        requestHash,
        jsonResponse(
          requestToPerform,
          crypto.getRandomValues(new Uint32Array(1))[0]
        ),
      ];
    } else if (requestToPerform.url === "elm-pages-internal://now") {
      return [requestHash, jsonResponse(requestToPerform, Date.now())];
    } else if (requestToPerform.url === "elm-pages-internal://env") {
      return [requestHash, await runEnvJob(requestToPerform, patternsToWatch)];
    } else if (requestToPerform.url === "elm-pages-internal://encrypt") {
      return [
        requestHash,
        await runEncryptJob(requestToPerform, patternsToWatch),
      ];
    } else if (requestToPerform.url === "elm-pages-internal://decrypt") {
      return [
        requestHash,
        await runDecryptJob(requestToPerform, patternsToWatch),
      ];
    } else if (requestToPerform.url === "elm-pages-internal://write-file") {
      return [requestHash, await runWriteFileJob(requestToPerform)];
    } else if (requestToPerform.url === "elm-pages-internal://sleep") {
      return [requestHash, await runSleep(requestToPerform)];
    } else if (requestToPerform.url === "elm-pages-internal://which") {
      return [requestHash, await runWhich(requestToPerform)];
    } else if (requestToPerform.url === "elm-pages-internal://question") {
      return [requestHash, await runQuestion(requestToPerform)];
    } else if (requestToPerform.url === "elm-pages-internal://shell") {
      return [requestHash, await runShell(requestToPerform)];
    } else if (requestToPerform.url === "elm-pages-internal://stream") {
      return [requestHash, await runStream(requestToPerform, portsFile)];
    } else if (requestToPerform.url === "elm-pages-internal://start-spinner") {
      return [requestHash, runStartSpinner(requestToPerform)];
    } else if (requestToPerform.url === "elm-pages-internal://stop-spinner") {
      return [requestHash, runStopSpinner(requestToPerform)];
    } else {
      throw `Unexpected internal BackendTask request format: ${kleur.yellow(
        JSON.stringify(2, null, requestToPerform)
      )}`;
    }
  } catch (error) {
    sendError(app, error);
  }
}

async function readFileJobNew(req, patternsToWatch) {
  const filePath = req.body.args[1];
  try {
    patternsToWatch.add(filePath);

    const fileContents = (await fsPromises.readFile(filePath)).toString();
    // TODO does this throw an error if there is invalid frontmatter?
    const parsedFile = matter(fileContents);

    return jsonResponse(req, {
      parsedFrontmatter: parsedFile.data,
      withoutFrontmatter: parsedFile.content,
      rawFile: fileContents,
    });
  } catch (error) {
    return jsonResponse(req, {
      errorCode: error.code,
    });
  }
}

function runSleep(req) {
  const { milliseconds } = req.body.args[0];
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve(jsonResponse(req, null));
    }, milliseconds);
  });
}

async function runWhich(req) {
  const command = req.body.args[0];
  try {
    return jsonResponse(req, await which(command));
  } catch (error) {
    return jsonResponse(req, null);
  }
}

async function runQuestion(req) {
  return jsonResponse(req, await question(req.body.args[0]));
}
function runStream(req, portsFile) {
  return new Promise(async (resolve) => {
    let lastStream = null;
    try {
      const cwd = path.resolve(...req.dir);
      const quiet = req.quiet;
      const env = { ...process.env, ...req.env };
      const kind = req.body.args[0].kind;
      const parts = req.body.args[0].parts;
      let index = 0;

      for (const part of parts) {
        let isLastProcess = index === parts.length - 1;
        let thisStream;
        if (
          false &&
          isLastProcess &&
          (kind === "command" || kind === "commandCode")
        ) {
          const { command, args } = part;
          let stdio;
          if (kind === "command") {
            stdio = ["pipe", "pipe", "pipe"];
          } else if (kind === "commandCode") {
            stdio = quiet
              ? ["pipe", "ignore", "ignore"]
              : ["pipe", "inherit", "inherit"];
          } else {
            throw new Error(`Unknown kind: ${kind}`);
          }
          const newProcess = spawnCallback(command, args, {
            stdio,
            cwd: cwd,
            env: env,
          });
          lastStream && lastStream.pipe(newProcess.stdin);
          if (kind === "command") {
            let stdoutOutput = "";
            let stderrOutput = "";
            let combinedOutput = "";
            newProcess.stderr.on("data", function (data) {
              stderrOutput += data;
              combinedOutput += data;
            });
            newProcess.stdout.on("data", function (data) {
              stdoutOutput += data;
              combinedOutput += data;
            });
            newProcess.on("close", async (exitCode) => {
              resolve(
                jsonResponse(req, {
                  body: "TODO",
                  metadata: {
                    stdoutOutput,
                    stderrOutput,
                    combinedOutput,
                    exitCode,
                  },
                })
              );
            });
          } else {
            newProcess.on("close", async (exitCode) => {
              resolve(jsonResponse(req, { exitCode }));
            });
          }
        } else {
          thisStream = await pipePartToStream(
            lastStream,
            part,
            { cwd, quiet, env },
            portsFile,
            (value) => resolve(jsonResponse(req, value)),
            isLastProcess
          );
        }
        lastStream = thisStream;
        index += 1;
      }
      if (kind === "json") {
        resolve(
          jsonResponse(req, {
            body: await consumers.json(lastStream),
            metadata: {
              // TODO
              stdoutOutput: "",
              stderrOutput: "",
              combinedOutput: "",
              exitCode: 0,
            },
          })
        );
      } else if (kind === "text") {
        resolve(
          jsonResponse(req, {
            body: await consumers.text(lastStream),
            metadata: {
              // TODO
              stdoutOutput: "",
              stderrOutput: "",
              combinedOutput: "",
              exitCode: 0,
            },
          })
        );
      } else if (kind === "none") {
        // lastStream.once("finish", async () => {
        //   resolve(jsonResponse(req, null));
        // });
        lastStream.once("close", () => {
          resolve(
            jsonResponse(req, {
              body: null,
              metadata: {
                // TODO
                stdoutOutput: "",
                stderrOutput: "",
                combinedOutput: "",
                exitCode: 0,
              },
            })
          );
        });
      } else if (kind === "command") {
        // already handled in parts.forEach
      }

      // lastStream.once("error", (error) => {
      //   console.log('Stream error!');
      //   console.error(error);
      //   reject(jsonResponse(req, null));
      // });
    } catch (error) {
      if (lastStream) {
        lastStream.destroy();
      }

      resolve(jsonResponse(req, { error: error.toString() }));
    }
  });
}

/**
 *
 * @param {import('node:stream').Stream} lastStream
 * @param {{ name: string }} part
 * @param {{cwd: string, quiet: boolean, env: object}} param2
 * @returns
 */
async function pipePartToStream(
  lastStream,
  part,
  { cwd, quiet, env },
  portsFile,
  resolve,
  isLastProcess
) {
  if (verbosity > 1 && !quiet) {
  }
  if (part.name === "stdout") {
    return lastStream.pipe(process.stdout);
  } else if (part.name === "stderr") {
    return lastStream.pipe(process.stderr);
  } else if (part.name === "stdin") {
    return process.stdin;
  } else if (part.name === "fileRead") {
    return fs.createReadStream(path.resolve(cwd, part.path));
  } else if (part.name === "customDuplex") {
    // console.log(part);
    const newLocal = await portsFile[part.portName](part.input, {
      cwd,
      quiet,
      env,
    });
    if (validateStream.isDuplexStream(newLocal)) {
      console.log("Piping to duplex stream!", part.portName);
      lastStream.pipe(newLocal);
      return newLocal;
    } else {
      throw `Expected '${part.portName}' to be a duplex stream!`;
    }
  } else if (part.name === "customRead") {
    return portsFile[part.portName](part.input, { cwd, quiet, env });
  } else if (part.name === "customWrite") {
    return portsFile[part.portName](part.input, { cwd, quiet, env });
  } else if (part.name === "gzip") {
    return lastStream.pipe(zlib.createGzip());
  } else if (part.name === "unzip") {
    return lastStream.pipe(zlib.createUnzip());
  } else if (part.name === "fileWrite") {
    return lastStream.pipe(fs.createWriteStream(path.resolve(part.path)));
  } else if (part.name === "httpWrite") {
    const makeFetchHappen = makeFetchHappenOriginal.defaults({
      // cache: mode === "build" ? "no-cache" : "default",
      cache: "default",
    });
    const response = await makeFetchHappen(part.url, {
      body: lastStream,
      duplex: "half",
      redirect: "follow",
      method: part.method,
      headers: part.headers,
      retry: part.retries,
      timeout: part.timeoutInMs,
    });
    // TODO what if there is an error?
    let metadata = {
      headers: Object.fromEntries(response.headers.entries()),
      statusCode: response.status,
      // bodyKind,
      url: response.url,
      statusText: response.statusText,
    };
    // return { stream: response.body, metadata };
    return response.body;
  } else if (part.name === "command") {
    const { command, args, allowNon0Status } = part;
    /**
     * @type {import('node:child_process').ChildProcess}
     */
    const newProcess = spawnCallback(command, args, {
      stdio: ["pipe", "pipe", "pipe"],
      cwd: cwd,
      env: env,
    });
    // newProcess.on("error", (error) => {
    //   console.error("ERROR in pipeline!", error);
    //   process.exit(1);
    // });
    // newProcess.on("exit", (code) => {
    //   console.log("Exit code:", code);
    //   if (code !== 0) {
    //     if (allowNon0Status) {
    //     } else {
    //       // TODO return correct body... or why is exit code 1?
    //       console.error("ERROR in exit code!", code);
    //       process.exit(1);
    //     }
    //   }
    // });
    lastStream && lastStream.pipe(newProcess.stdin);
    return newProcess.stdout;
  } else if (part.name === "fromString") {
    return Readable.from([part.string]);
  } else {
    // console.error(`Unknown stream part: ${part.name}!`);
    // process.exit(1);
    throw `Unknown stream part: ${part.name}!`;
  }
}

async function runShell(req) {
  const cwd = path.resolve(...req.dir);
  const quiet = req.quiet;
  const env = { ...process.env, ...req.env };
  const captureOutput = req.body.args[0].captureOutput;
  if (req.body.args[0].commands.length === 1) {
    return jsonResponse(
      req,
      await shell({ cwd, quiet, env, captureOutput }, req.body.args[0])
    );
  } else {
    return jsonResponse(
      req,
      await pipeShells({ cwd, quiet, env, captureOutput }, req.body.args[0])
    );
  }
}

function commandAndArgsToString(cwd, commandsAndArgs) {
  return (
    `$ ` +
    commandsAndArgs.commands
      .map((commandAndArgs) => {
        return [commandAndArgs.command, ...commandAndArgs.args].join(" ");
      })
      .join(" | ")
  );
}

export function shell({ cwd, quiet, env, captureOutput }, commandAndArgs) {
  return new Promise((resolve, reject) => {
    const command = commandAndArgs.commands[0].command;
    const args = commandAndArgs.commands[0].args;
    if (verbosity > 1 && !quiet) {
      console.log(commandAndArgsToString(cwd, commandAndArgs));
    }
    if (!captureOutput && !quiet) {
      const subprocess = spawnCallback(command, args, {
        stdio: quiet
          ? ["inherit", "ignore", "ignore"]
          : ["inherit", "inherit", "inherit"],
        cwd: cwd,
        env: env,
      });
      subprocess.on("close", async (code) => {
        resolve({
          output: "",
          errorCode: code,
          stderrOutput: "",
          stdoutOutput: "",
        });
      });
    } else {
      const subprocess = spawnCallback(command, args, {
        stdio: ["pipe", "pipe", "pipe"],
        cwd: cwd,
        env: env,
      });
      let commandOutput = "";
      let stderrOutput = "";
      let stdoutOutput = "";

      if (verbosity > 0 && !quiet) {
        subprocess.stdout.pipe(process.stdout);
        subprocess.stderr.pipe(process.stderr);
      }
      subprocess.stderr.on("data", function (data) {
        commandOutput += data;
        stderrOutput += data;
      });
      subprocess.stdout.on("data", function (data) {
        commandOutput += data;
        stdoutOutput += data;
      });

      subprocess.on("close", async (code) => {
        resolve({
          output: commandOutput,
          errorCode: code,
          stderrOutput,
          stdoutOutput,
        });
      });
    }
  });
}

/**
 * @typedef {{ command: string, args: string[], timeout: number? }} ElmCommand
 */

/**
 * @param {{ commands: ElmCommand[] }} commandsAndArgs
 */
export function pipeShells(
  { cwd, quiet, env, captureOutput },
  commandsAndArgs
) {
  return new Promise((resolve, reject) => {
    if (verbosity > 1 && !quiet) {
      console.log(commandAndArgsToString(cwd, commandsAndArgs));
    }

    /**
     * @type {null | import('node:child_process').ChildProcess}
     */
    let previousProcess = null;
    let currentProcess = null;

    commandsAndArgs.commands.forEach(({ command, args, timeout }, index) => {
      let isLastProcess = index === commandsAndArgs.commands.length - 1;
      /**
       * @type {import('node:child_process').ChildProcess}
       */
      if (previousProcess === null) {
        currentProcess = spawnCallback(command, args, {
          stdio: ["inherit", "pipe", "inherit"],
          timeout: timeout ? undefined : timeout,
          cwd: cwd,
          env: env,
        });
      } else {
        if (isLastProcess && !captureOutput && false) {
          currentProcess = spawnCallback(command, args, {
            stdio: quiet
              ? ["pipe", "ignore", "ignore"]
              : ["pipe", "inherit", "inherit"],
            timeout: timeout ? undefined : timeout,
            cwd: cwd,
            env: env,
          });
        } else {
          currentProcess = spawnCallback(command, args, {
            stdio: ["pipe", "pipe", "pipe"],
            timeout: timeout ? undefined : timeout,
            cwd: cwd,
            env: env,
          });
        }
        previousProcess.stdout.pipe(currentProcess.stdin);
      }
      previousProcess = currentProcess;
    });

    if (currentProcess === null) {
      reject("");
    } else {
      let commandOutput = "";
      let stderrOutput = "";
      let stdoutOutput = "";

      if (verbosity > 0 && !quiet) {
        currentProcess.stdout && currentProcess.stdout.pipe(process.stdout);
        currentProcess.stderr && currentProcess.stderr.pipe(process.stderr);
      }

      currentProcess.stderr &&
        currentProcess.stderr.on("data", function (data) {
          commandOutput += data;
          stderrOutput += data;
        });
      currentProcess.stdout &&
        currentProcess.stdout.on("data", function (data) {
          commandOutput += data;
          stdoutOutput += data;
        });

      currentProcess.on("close", async (code) => {
        resolve({
          output: commandOutput,
          errorCode: code,
          stderrOutput,
          stdoutOutput,
        });
      });
    }
  });
}

export async function question({ prompt }) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    return rl.question(prompt, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

async function runWriteFileJob(req) {
  const data = req.body.args[0];
  try {
    await fsPromises.mkdir(path.dirname(data.path), { recursive: true });
    await fsPromises.writeFile(data.path, data.body);
    return jsonResponse(req, null);
  } catch (error) {
    console.trace(error);
    throw {
      title: "BackendTask Error",
      message: `BackendTask.Generator.writeFile failed for file path: ${kleur.yellow(
        data.path
      )}\n${kleur.red(error.toString())}`,
    };
  }
}

function runStartSpinner(req) {
  const data = req.body.args[0];
  let spinnerId;

  if (data.spinnerId) {
    spinnerId = data.spinnerId;
    // TODO use updateSpinnerState?
    spinnies.update(spinnerId, { text: data.text, status: "spinning" });
  } else {
    spinnerId = Math.random().toString(36);
    // spinnies.add(spinnerId, { text: data.text, status: data.immediateStart ? 'spinning' : 'stopped' });
    spinnies.add(spinnerId, { text: data.text, status: "spinning" });
    // }
  }
  return jsonResponse(req, spinnerId);
}

function runStopSpinner(req) {
  const data = req.body.args[0];
  const { spinnerId, completionText, completionFn } = data;
  let completeFn;
  if (completionFn === "succeed") {
    spinnies.succeed(spinnerId, { text: completionText });
  } else if (completionFn === "fail") {
    spinnies.fail(spinnerId, { text: completionText });
  } else {
    console.log("Unexpected");
  }
  return jsonResponse(req, null);
}

async function runGlobNew(req, patternsToWatch) {
  try {
    const { pattern, options } = req.body.args[0];
    const cwd = path.resolve(...req.dir);
    const matchedPaths = await globby.globby(pattern, {
      ...options,
      stats: true,
      cwd,
    });
    patternsToWatch.add(pattern);

    return jsonResponse(
      req,
      matchedPaths.map((fullPath) => {
        const stats = fullPath.stats;
        if (!stats) {
          return null;
        }
        return {
          fullPath: fullPath.path,
          captures: mm.capture(pattern, fullPath.path),
          fileStats: {
            size: stats.size,
            atime: Math.round(stats.atime.getTime()),
            mtime: Math.round(stats.mtime.getTime()),
            ctime: Math.round(stats.ctime.getTime()),
            birthtime: Math.round(stats.birthtime.getTime()),
            fullPath: fullPath.path,
            isDirectory: stats.isDirectory(),
          },
        };
      })
    );
  } catch (e) {
    console.log(`Error performing glob '${JSON.stringify(req.body)}'`);
    throw e;
  }
}

async function runLogJob(req) {
  try {
    console.log(req.body.args[0].message);
    return jsonResponse(req, null);
  } catch (e) {
    console.log(`Error performing env '${JSON.stringify(req.body)}'`);
    throw e;
  }
}
async function runEnvJob(req, patternsToWatch) {
  try {
    const expectedEnv = req.body.args[0];
    return jsonResponse(req, process.env[expectedEnv] || null);
  } catch (e) {
    console.log(`Error performing env '${JSON.stringify(req.body)}'`);
    throw e;
  }
}
async function runEncryptJob(req, patternsToWatch) {
  try {
    return jsonResponse(
      req,
      cookie.sign(
        JSON.stringify(req.body.args[0].values, null, 0),
        req.body.args[0].secret
      )
    );
  } catch (e) {
    throw {
      title: "BackendTask Encrypt Error",
      message:
        e.toString() + e.stack + "\n\n" + JSON.stringify(rawRequest, null, 2),
    };
  }
}
async function runDecryptJob(req, patternsToWatch) {
  try {
    // TODO if unsign returns `false`, need to have an `Err` in Elm because decryption failed
    const signed = tryDecodeCookie(
      req.body.args[0].input,
      req.body.args[0].secrets
    );

    return jsonResponse(req, JSON.parse(signed || "null"));
  } catch (e) {
    throw {
      title: "BackendTask Decrypt Error",
      message:
        e.toString() + e.stack + "\n\n" + JSON.stringify(rawRequest, null, 2),
    };
  }
}

/**
 * @param {{ ports: { fromJsPort: { send: (arg0: { tag: string; data: any; }) => void; }; }; }} app
 * @param {{ message: string; title: string; }} error
 */
function sendError(app, error) {
  foundErrors = true;

  app.ports.fromJsPort.send({
    tag: "BuildError",
    data: error,
  });
}
function tryDecodeCookie(input, secrets) {
  if (secrets.length > 0) {
    const signed = cookie.unsign(input, secrets[0]);
    if (signed) {
      return signed;
    } else {
      return tryDecodeCookie(input, secrets.slice(1));
    }
  } else {
    return null;
  }
}
