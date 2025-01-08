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
import { Readable, Writable } from "node:stream";
import * as validateStream from "./validate-stream.js";
import { default as makeFetchHappenOriginal } from "make-fetch-happen";
import mergeStreams from "@sindresorhus/merge-streams";

let verbosity = 2;
const spinnies = new Spinnies();

process.on("unhandledRejection", (error) => {
  console.error(error);
});

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
 * @param {string} versionMessage
 */
export async function runGenerator(
  cliOptions,
  portsFile,
  elmModule,
  scriptModuleName,
  versionMessage
) {
  // const { fs, resetInMemoryFs } = require("./request-cache-fs.js")(true);
  // resetInMemoryFs();
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
      true,
      versionMessage
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
 * @param {string} versionMessage
 */
function runGeneratorAppHelp(
  cliOptions,
  portsFile,
  basePath,
  elmModule,
  scriptModuleName,
  mode,
  pagePath,
  hasFsAccess,
  versionMessage
) {
  const isDevServer = mode !== "build";
  let patternsToWatch = new Set();
  let app = null;
  let killApp;
  // Handle version flag with early return
  if (
    cliOptions.length === 1 &&
    (cliOptions[0] === "--version" || cliOptions[0] === "-v")
  ) {
    console.log(versionMessage);
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    const isBytes = pagePath.match(/content\.dat\/?$/);

    app = elmModule.Elm.ScriptMain.init({
      flags: {
        compatibilityKey,
        argv: ["", `elm-pages run ${scriptModuleName}`, ...cliOptions],
        versionMessage: versionMessage || "",
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
        doHttp(app, fromElm, mode, patternsToWatch, portsFile);
      } else if (fromElm.tag === "Errors") {
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
        doHttp(app, fromElm, mode, patternsToWatch, portsFile);
      } else if (fromElm.tag === "Errors") {
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

async function doHttp(app, fromElm, mode, patternsToWatch, portsFile) {
  const promises = fromElm.args[0].map(
    async ([requestHash, requestToPerform]) => {
      const response = await runJob(
        requestToPerform,
        app,
        mode,
        patternsToWatch,
        portsFile
      );
      return [
        requestHash,
        {
          request: requestToPerform,
          response: response,
        },
      ];
    }
  );
  const entries = await Promise.all(promises);
  app.ports.gotBatchSub.send(Object.fromEntries(entries));
}

async function runJob(requestToPerform, app, mode, patternsToWatch, portsFile) {
  try {
    if (
      requestToPerform.url !== "elm-pages-internal://port" &&
      requestToPerform.url.startsWith("elm-pages-internal://")
    ) {
      return {
        bodyKind: "json",
        body: await runInternalJob(
          requestToPerform,
          patternsToWatch,
          portsFile
        ),
      };
    } else {
      return await runHttpJob(requestToPerform, mode, portsFile);
    }
  } catch (error) {
    sendError(app, error);
    return { bodyKind: "json", body: null };
  }
}

/** @typedef { { route : string; contentJson : string; head : SeoTag[]; html: string; } } FromElm */
/** @typedef {HeadTag | JsonLdTag} SeoTag */
/** @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag */
/** @typedef {{ contents: Object; type: 'json-ld' }} JsonLdTag */
/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */
/** @typedef { { head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */

async function runHttpJob(requestToPerform, mode, portsFile) {
  const lookupResponse = await lookupOrPerform(
    portsFile,
    mode,
    requestToPerform
  );

  if (lookupResponse.kind === "cache-response-path") {
    const responseFilePath = lookupResponse.value;
    return JSON.parse(
      (await fs.promises.readFile(responseFilePath, "utf8")).toString()
    );
  } else if (lookupResponse.kind === "response-json") {
    return lookupResponse.value;
  } else {
    throw `Unexpected kind ${lookupResponse}`;
  }
}

async function runInternalJob(requestToPerform, patternsToWatch, portsFile) {
  const cwd = path.resolve(...requestToPerform.dir);
  const quiet = requestToPerform.quiet;
  const env = { ...process.env, ...requestToPerform.env };

  const context = { cwd, quiet, env };
  switch (requestToPerform.url) {
    case "elm-pages-internal://log":
      return await runLogJob(requestToPerform);
    case "elm-pages-internal://read-file":
      return await readFileJobNew(requestToPerform, patternsToWatch, context);
    case "elm-pages-internal://glob":
      return await runGlobNew(requestToPerform, patternsToWatch);
    case "elm-pages-internal://randomSeed":
      return crypto.getRandomValues(new Uint32Array(1))[0];
    case "elm-pages-internal://now":
      return Date.now();
    case "elm-pages-internal://env":
      return await runEnvJob(requestToPerform);
    case "elm-pages-internal://encrypt":
      return await runEncryptJob(requestToPerform);
    case "elm-pages-internal://decrypt":
      return await runDecryptJob(requestToPerform);
    case "elm-pages-internal://write-file":
      return await runWriteFileJob(requestToPerform, context);
    case "elm-pages-internal://sleep":
      return await runSleep(requestToPerform);
    case "elm-pages-internal://which":
      return await runWhich(requestToPerform);
    case "elm-pages-internal://question":
      return await runQuestion(requestToPerform);
    case "elm-pages-internal://shell":
      return await runShell(requestToPerform);
    case "elm-pages-internal://stream":
      return await runStream(requestToPerform, portsFile, context);
    case "elm-pages-internal://start-spinner":
      return runStartSpinner(requestToPerform);
    case "elm-pages-internal://stop-spinner":
      return runStopSpinner(requestToPerform);
    default:
      throw `Unexpected internal BackendTask request format: ${kleur.yellow(
        JSON.stringify(2, null, requestToPerform)
      )}`;
  }
}

async function readFileJobNew(req, patternsToWatch, { cwd }) {
  // TODO use cwd
  const filePath = path.resolve(cwd, req.body.args[1]);
  try {
    patternsToWatch.add(filePath);

    const fileContents = (await fsPromises.readFile(filePath)).toString();
    // TODO does this throw an error if there is invalid frontmatter?
    const parsedFile = matter(fileContents);

    return {
      parsedFrontmatter: parsedFile.data,
      withoutFrontmatter: parsedFile.content,
      rawFile: fileContents,
    };
  } catch (error) {
    return {
      errorCode: error.code,
    };
  }
}

function runSleep(req) {
  const { milliseconds } = req.body.args[0];
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve(null);
    }, milliseconds);
  });
}

async function runWhich(req) {
  const command = req.body.args[0];
  try {
    return await which(command);
  } catch (error) {
    return null;
  }
}

async function runQuestion(req) {
  return await question(req.body.args[0]);
}

function runStream(req, portsFile, context) {
  return new Promise(async (resolve) => {
    let metadataResponse = null;
    let lastStream = null;
    try {
      const kind = req.body.args[0].kind;
      const parts = req.body.args[0].parts;
      let index = 0;

      for (const part of parts) {
        let isLastProcess = index === parts.length - 1;
        let thisStream;
        const { stream, metadata } = await pipePartToStream(
          lastStream,
          part,
          context,
          portsFile,
          resolve,
          isLastProcess,
          kind
        );
        metadataResponse = metadata;
        thisStream = stream;

        lastStream = thisStream;
        index += 1;
      }
      switch (kind) {
        case "json":
          resolve({
            body: await consumers.json(lastStream),
            metadata: await tryCallingFunction(metadataResponse),
          });
          break;
        case "text":
          resolve({
            body: await consumers.text(lastStream),
            metadata: await tryCallingFunction(metadataResponse),
          });
          break;
        case "none":
          if (!lastStream) {
            // ensure all error handling gets a chance to fire before resolving successfully
            await tryCallingFunction(metadataResponse);
            resolve({ body: null });
          } else {
            let resolvedMeta = await tryCallingFunction(metadataResponse);
            lastStream.once("finish", async () => {
              resolve({
                body: null,
                metadata: resolvedMeta,
              });
            });
            lastStream.once("end", async () => {
              resolve({
                body: null,
                metadata: resolvedMeta,
              });
            });
          }
          break;
        case "command":
          // already handled in parts.forEach
          break;
        default:
          break;
      }

      async function pipePartToStream(
        lastStream,
        part,
        { cwd, quiet, env },
        portsFile,
        resolve,
        isLastProcess,
        kind
      ) {
        switch (part.name) {
          case "stdout":
            return { stream: pipeIfPossible(lastStream, stdout()) };
          case "stderr":
            return { stream: pipeIfPossible(lastStream, stderr()) };
          case "stdin":
            return { stream: process.stdin };
          case "fileRead": {
            const newLocal = fs.createReadStream(path.resolve(cwd, part.path));
            newLocal.once("error", (error) => {
              newLocal.close();
              resolve({ error: error.toString() });
            });
            return { stream: newLocal };
          }
          case "customDuplex": {
            const newLocal = await portsFile[part.portName](part.input, {
              cwd,
              quiet,
              env,
            });
            if (validateStream.isDuplexStream(newLocal.stream)) {
              pipeIfPossible(lastStream, newLocal.stream);
              return newLocal;
            } else {
              throw `Expected '${part.portName}' to be a duplex stream!`;
            }
          }
          case "customRead": {
            return {
              metadata: null,
              stream: await portsFile[part.portName](part.input, {
                cwd,
                quiet,
                env,
              }),
            };
          }
          case "customWrite": {
            const newLocal = await portsFile[part.portName](part.input, {
              cwd,
              quiet,
              env,
            });
            if (!validateStream.isWritableStream(newLocal.stream)) {
              console.error("Expected a writable stream!");
              resolve({ error: "Expected a writable stream!" });
            } else {
              pipeIfPossible(lastStream, newLocal.stream);
            }
            return newLocal;
          }
          case "gzip": {
            const gzip = zlib.createGzip();
            if (!lastStream) {
              gzip.end();
            }
            return {
              metadata: null,
              stream: pipeIfPossible(lastStream, gzip),
            };
          }
          case "unzip": {
            return {
              metadata: null,
              stream: pipeIfPossible(lastStream, zlib.createUnzip()),
            };
          }
          case "fileWrite": {
            const destinationPath = path.resolve(part.path);
            try {
              await fsPromises.mkdir(path.dirname(destinationPath), {
                recursive: true,
              });
            } catch (error) {
              resolve({ error: error.toString() });
            }
            const newLocal = fs.createWriteStream(destinationPath);
            newLocal.once("error", (error) => {
              newLocal.close();
              newLocal.removeAllListeners();
              resolve({ error: error.toString() });
            });
            return {
              metadata: null,
              stream: pipeIfPossible(lastStream, newLocal),
            };
          }
          case "httpWrite": {
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
            if (!isLastProcess && !response.ok) {
              resolve({
                error: `HTTP request failed: ${response.status} ${response.statusText}`,
              });
            } else {
              let metadata = () => {
                return {
                  headers: Object.fromEntries(response.headers.entries()),
                  statusCode: response.status,
                  // bodyKind,
                  url: response.url,
                  statusText: response.statusText,
                };
              };
              return { metadata, stream: response.body };
            }
          }
          case "command": {
            const { command, args, allowNon0Status, output } = part;
            /** @type {'ignore' | 'inherit'} } */
            let letPrint = quiet ? "ignore" : "inherit";
            let stderrKind =
              kind === "none" && isLastProcess ? letPrint : "pipe";
            if (output === "Ignore") {
              stderrKind = "ignore";
            } else if (output === "Print") {
              stderrKind = letPrint;
            }

            const stdoutKind =
              (output === "InsteadOfStdout" || kind === "none") && isLastProcess
                ? letPrint
                : "pipe";
            /**
             * @type {import('node:child_process').ChildProcess}
             */
            const newProcess = spawnCallback(command, args, {
              stdio: [
                "pipe",
                // if we are capturing stderr instead of stdout, print out stdout with `inherit`
                stdoutKind,
                stderrKind,
              ],
              cwd: cwd,
              env: env,
            });

            pipeIfPossible(lastStream, newProcess.stdin);
            let newStream;
            if (output === "MergeWithStdout") {
              newStream = mergeStreams([newProcess.stdout, newProcess.stderr]);
            } else if (output === "InsteadOfStdout") {
              newStream = newProcess.stderr;
            } else {
              newStream = newProcess.stdout;
            }

            newProcess.once("error", (error) => {
              newStream && newStream.end();
              newProcess.removeAllListeners();
              resolve({ error: error.toString() });
            });
            if (isLastProcess) {
              return {
                stream: newStream,
                metadata: new Promise((resoveMeta) => {
                  newProcess.once("exit", (code) => {
                    if (code !== 0 && !allowNon0Status) {
                      newStream && newStream.end();
                      resolve({
                        error: `Command ${command} exited with code ${code}`,
                      });
                    }

                    resoveMeta({
                      exitCode: code,
                    });
                  });
                }),
              };
            } else {
              return { metadata: null, stream: newStream };
            }
          }
          case "fromString": {
            return { stream: Readable.from([part.string]), metadata: null };
          }
          default: {
            // console.error(`Unknown stream part: ${part.name}!`);
            // process.exit(1);
            throw `Unknown stream part: ${part.name}!`;
          }
        }
      }
    } catch (error) {
      if (lastStream) {
        lastStream.destroy();
      }

      resolve({ error: error.toString() });
    }
  });
}

/**
 * @param { import('stream').Stream? } input
 * @param {import('stream').Writable | import('stream').Duplex} destination
 */
function pipeIfPossible(input, destination) {
  if (input) {
    return input.pipe(destination);
  } else {
    return destination;
  }
}

function stdout() {
  return new Writable({
    write(chunk, encoding, callback) {
      process.stdout.write(chunk, callback);
    },
  });
}

function stderr() {
  return new Writable({
    write(chunk, encoding, callback) {
      process.stderr.write(chunk, callback);
    },
  });
}

async function tryCallingFunction(func) {
  if (func) {
    // if is promise
    if (func.then) {
      return await func;
    }
    // if is function
    else if (typeof func === "function") {
      return await func();
    }
  } else {
    return func;
  }
}

async function runShell(req) {
  const cwd = path.resolve(...req.dir);
  const quiet = req.quiet;
  const env = { ...process.env, ...req.env };
  const captureOutput = req.body.args[0].captureOutput;
  if (req.body.args[0].commands.length === 1) {
    return await shell({ cwd, quiet, env, captureOutput }, req.body.args[0]);
  } else {
    return await pipeShells(
      { cwd, quiet, env, captureOutput },
      req.body.args[0]
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
 * @param {*} _
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

async function runWriteFileJob(req, { cwd }) {
  const data = req.body.args[0];
  const filePath = path.resolve(cwd, data.path);
  try {
    await fsPromises.mkdir(path.dirname(filePath), { recursive: true });
    await fsPromises.writeFile(filePath, data.body);
    return null;
  } catch (error) {
    console.trace(error);
    throw {
      title: "BackendTask Error",
      message: `BackendTask.Generator.writeFile failed for file path: ${kleur.yellow(
        filePath
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
  return spinnerId;
}

function runStopSpinner(req) {
  const data = req.body.args[0];
  const { spinnerId, completionText, completionFn } = data;
  if (completionFn === "succeed") {
    spinnies.succeed(spinnerId, { text: completionText });
  } else if (completionFn === "fail") {
    spinnies.fail(spinnerId, { text: completionText });
  } else {
    console.log("Unexpected");
  }
  return null;
}

async function runGlobNew(req, patternsToWatch) {
  const { pattern, options } = req.body.args[0];
  const cwd = path.resolve(...req.dir);
  const matchedPaths = await globby.globby(pattern, {
    ...options,
    stats: true,
    cwd,
  });
  patternsToWatch.add(pattern);

  return matchedPaths.map((fullPath) => {
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
  });
}

async function runLogJob(req) {
  try {
    console.log(req.body.args[0].message);
    return null;
  } catch (e) {
    console.log(`Error performing env '${JSON.stringify(req.body)}'`);
    throw e;
  }
}

async function runEnvJob(req) {
  try {
    const expectedEnv = req.body.args[0];
    return process.env[expectedEnv] || null;
  } catch (e) {
    console.log(`Error performing env '${JSON.stringify(req.body)}'`);
    throw e;
  }
}

async function runEncryptJob(req) {
  try {
    return cookie.sign(
      JSON.stringify(req.body.args[0].values, null, 0),
      req.body.args[0].secret
    );
  } catch (e) {
    throw {
      title: "BackendTask Encrypt Error",
      message:
        e.toString() + e.stack + "\n\n" + JSON.stringify(rawRequest, null, 2),
    };
  }
}

async function runDecryptJob(req) {
  try {
    // TODO if unsign returns `false`, need to have an `Err` in Elm because decryption failed
    const signed = tryDecodeCookie(
      req.body.args[0].input,
      req.body.args[0].secrets
    );

    return JSON.parse(signed || "null");
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
  app.ports.fromJsPort.send({
    tag: "BuildError",
    data: error,
  });
}

/**
 *
 * @param {string} input
 * @param {(crypto.BinaryLike | crypto.KeyObject)[]} secrets
 * @returns
 */
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
