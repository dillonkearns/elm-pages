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
import { tuiParseSingleEvent, tuiParseAllEvents } from "./tui-parser.js";
import { Spinnies } from "./spinnies/index.js";
import { default as which } from "which";
import * as readline from "readline";
import { spawn as spawnCallback } from "cross-spawn";
import * as consumers from "stream/consumers";
import * as os from "node:os";
import * as zlib from "node:zlib";
import { Readable, Writable } from "node:stream";
import * as validateStream from "./validate-stream.js";
import { default as makeFetchHappenOriginal } from "make-fetch-happen";
import mergeStreams from "@sindresorhus/merge-streams";
import { parseDbBinHeader, buildDbBin } from "./db-bin-format.js";

function detectColorSupport() {
  const env = process.env;
  if ("FORCE_COLOR" in env) {
    return env.FORCE_COLOR !== "0" && env.FORCE_COLOR !== "false";
  }
  if ("NO_COLOR" in env) return false;
  if (env.TERM === "dumb") return false;
  if (!process.stdout.isTTY) return false;
  if (env.CI && (env.GITHUB_ACTIONS || env.GITLAB_CI || env.CIRCLECI))
    return true;
  return true;
}

let verbosity = 2;
const spinnies = new Spinnies();
let configuredDbPath = "db.bin";

process.on("unhandledRejection", (error) => {
  console.error(error);
});
let foundErrors;

/**
 * @typedef {{ [x: string]: (arg0: unknown, arg1: { cwd: string; quiet: boolean; env: NodeJS.ProcessEnv; }) => unknown; }} PortsFile
 */

/**
 * @param {string} basePath
 * @param {unknown} elmModule
 * @param {string} path
 * @param {{method: string;hostname: string;query: Record<string, string | undefined>;headers: Record<string, string>;host: string;pathname: string;port: number | null;protocol: string;rawUrl: string;}} request
 * @param {(pattern: string) => void} addBackendTaskWatcher
 * @param {boolean} hasFsAccess
 * @returns
 * @param {PortsFile} portsFile
 * @param {string} mode
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
  configuredDbPath = "db.bin";
  const result = await runElmApp(
    portsFile,
    basePath,
    elmModule,
    mode,
    path,
    request,
    addBackendTaskWatcher
  );
  return result;
}

/**
 * @param {unknown} elmModule
 * @returns
 * @param {string[]} cliOptions
 * @param {PortsFile} portsFile
 * @param {string} scriptModuleName
 * @param {string} versionMessage
 * @param {{ suppressConsoleLogDuringInit?: boolean }} [options]
 */
export async function runGenerator(
  cliOptions,
  portsFile,
  elmModule,
  scriptModuleName,
  versionMessage,
  options = {}
) {
  global.isRunningGenerator = true;
  // const { fs, resetInMemoryFs } = require("./request-cache-fs.js")(true);
  // resetInMemoryFs();
  foundErrors = false;
  // since init/update are never called in pre-renders, and BackendTask.Http is called using pure NodeJS HTTP fetching
  // we can provide a fake HTTP instead of xhr2 (which is otherwise needed for Elm HTTP requests from Node)
  global.XMLHttpRequest = {};
  configuredDbPath = "db.bin";
  try {
    const result = await runGeneratorAppHelp(
      cliOptions,
      portsFile,
      "",
      elmModule,
      scriptModuleName,
      "production",
      "",
      versionMessage,
      options
    );
    return result;
  } catch (error) {
    process.exitCode = 1;
    console.log(restoreColorSafe(error));
  }
}

/**
 * @param {string} basePath
 * @param {unknown} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @returns {Promise<({is404: boolean;} & ({kind: 'json';contentJson: string;} | {kind: 'html';htmlString: string;} | {kind: 'api-response';body: string;}))>}
 * @param {string[]} cliOptions
 * @param {PortsFile} portsFile
 * @param {typeof import("fs") | import("memfs").IFs} fs
 * @param {string} scriptModuleName
 * @param {string} versionMessage
 * @param {{ suppressConsoleLogDuringInit?: boolean }} [options]
 */
function runGeneratorAppHelp(
  cliOptions,
  portsFile,
  basePath,
  elmModule,
  scriptModuleName,
  mode,
  pagePath,
  versionMessage,
  options = {}
) {
  const isDevServer = mode !== "build";
  /** @type {Set<string>} */
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
    const logOriginal = console.log;
    if (options.suppressConsoleLogDuringInit) {
      console.log = function () {};
    }

    try {
      app = elmModule.Elm.ScriptMain.init({
        flags: {
          compatibilityKey,
          argv: ["", `elm-pages run ${scriptModuleName}`, ...cliOptions],
          versionMessage: versionMessage || "",
          colorMode: detectColorSupport(),
        },
      });
    } finally {
      console.log = logOriginal;
    }

    killApp = () => {
      app.ports.toJsPort.unsubscribe(portHandler);
      app.die();
      app = null;
      // delete require.cache[require.resolve(compiledElmPath)];
    };

    async function portHandler(/** @type { FromElm } */ newThing) {
      // toJsPort now sends { json, bytes } where bytes carries raw Bytes data
      let fromElm = newThing.json;
      const outgoingBytes = newThing.bytes || [];
      let contentDatPayload;

      if (typeof fromElm === "string") {
        // printAndExitSuccess from Elm Cli.Program (e.g. --help output)
        console.log(fromElm);
        resolve();
        return;
      } else if (fromElm.command === "log") {
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
            // Include raw HTML for frozen view extraction
            html: args.html,
          });
        } else {
          resolve(
            outputString(basePath, fromElm, isDevServer, contentDatPayload)
          );
        }
      } else if (fromElm.tag === "DoHttp") {
        // Build a map of request hash → raw bytes from the port's bytes field
        const outgoingBytesMap = new Map(
          outgoingBytes.map(({ key, data }) => [key, dataViewToBuffer(data)])
        );
        const results = await Promise.all(
          fromElm.args[0].map(async ([requestHash, requestToPerform]) => {
            // Inject raw bytes into the request if available (for BytesBody)
            const reqBytes = outgoingBytesMap.get(requestHash);
            if (reqBytes) {
              requestToPerform.__rawBytes = reqBytes;
            }
            // Collect multipart bytes from port (keyed as "hash:multipart:index")
            const multipartPrefix = requestHash + ":multipart:";
            const multipartBytes = new Map();
            for (const [key, buf] of outgoingBytesMap) {
              if (key.startsWith(multipartPrefix)) {
                const idx = parseInt(key.slice(multipartPrefix.length));
                multipartBytes.set(idx, buf);
              }
            }
            if (multipartBytes.size > 0) {
              requestToPerform.__multipartBytes = multipartBytes;
            }
            let result;
            if (
              requestToPerform.url !== "elm-pages-internal://port" &&
              requestToPerform.url.startsWith("elm-pages-internal://")
            ) {
              [, result] = await runInternalJob(
                requestHash,
                app,
                requestToPerform,
                patternsToWatch,
                portsFile
              );
            } else {
              [, result] = await runHttpJob(
                requestHash,
                portsFile,
                mode,
                requestToPerform
              );
            }
            return {
              key: requestHash,
              json: { request: result.request, response: result.response },
              bytes: result.rawBytes ? bufferToDataView(result.rawBytes) : null,
            };
          })
        );
        app.ports.gotBatchSub.send(results);
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
 * @param {unknown} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @param {{ method: string; hostname: string; query: string; headers: unknown; host: string; pathname: string; port: string; protocol: string; rawUrl: string; }} request
 * @param {(task : string) => void} addBackendTaskWatcher
 * @param {PortsFile} portsFile
 * @returns {Promise<({is404: boolean} & ( { kind: 'json'; contentJson: string} | { kind: 'html'; htmlString: string } | { kind: 'api-response'; body: string; }) )>}
 */
function runElmApp(
  portsFile,
  basePath,
  elmModule,
  mode,
  pagePath,
  request,
  addBackendTaskWatcher
) {
  const isDevServer = mode !== "build";
  /** @type {Set<string>} */
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
      let outgoingBytes = [];
      if ("oldThing" in newThing) {
        // sendPageData port
        fromElm = newThing.oldThing;
        contentDatPayload = newThing.binaryPageData;
      } else if ("json" in newThing) {
        // toJsPort with new { json, bytes } format
        fromElm = newThing.json;
        outgoingBytes = newThing.bytes || [];
      } else {
        fromElm = newThing;
      }
      if (fromElm.command === "log") {
        console.log(fromElm.value);
      } else if (fromElm.tag === "ApiResponse") {
        const args = fromElm.args[0];
        const resolvedBody = contentDatPayload
          ? {
              ...args.body,
              body: Buffer.from(dataViewToBuffer(contentDatPayload)).toString(
                "base64"
              ),
            }
          : args.body;

        resolve({
          kind: "api-response",
          is404: args.is404,
          statusCode: args.statusCode,
          body: resolvedBody,
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
            // Include raw HTML for frozen view extraction
            html: args.html,
          });
        } else {
          resolve(
            outputString(basePath, fromElm, isDevServer, contentDatPayload)
          );
        }
      } else if (fromElm.tag === "DoHttp") {
        // Build a map of request hash → raw bytes from the port's bytes field
        const outgoingBytesMap = new Map(
          outgoingBytes.map(({ key, data }) => [key, dataViewToBuffer(data)])
        );
        const results = await Promise.all(
          fromElm.args[0].map(async ([requestHash, requestToPerform]) => {
            // Inject raw bytes into the request if available (for BytesBody)
            const reqBytes = outgoingBytesMap.get(requestHash);
            if (reqBytes) {
              requestToPerform.__rawBytes = reqBytes;
            }
            // Collect multipart bytes from port (keyed as "hash:multipart:index")
            const multipartPrefix = requestHash + ":multipart:";
            const multipartBytes = new Map();
            for (const [key, buf] of outgoingBytesMap) {
              if (key.startsWith(multipartPrefix)) {
                const idx = parseInt(key.slice(multipartPrefix.length));
                multipartBytes.set(idx, buf);
              }
            }
            if (multipartBytes.size > 0) {
              requestToPerform.__multipartBytes = multipartBytes;
            }
            let result;
            if (
              requestToPerform.url !== "elm-pages-internal://port" &&
              requestToPerform.url.startsWith("elm-pages-internal://")
            ) {
              [, result] = await runInternalJob(
                requestHash,
                app,
                requestToPerform,
                patternsToWatch,
                portsFile
              );
            } else {
              [, result] = await runHttpJob(
                requestHash,
                portsFile,
                mode,
                requestToPerform
              );
            }
            return {
              key: requestHash,
              json: { request: result.request, response: result.response },
              bytes: result.rawBytes ? bufferToDataView(result.rawBytes) : null,
            };
          })
        );
        app.ports.gotBatchSub.send(results);
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
 * @param {FromElmPageProgress} fromElm
 * @param {boolean} isDevServer
 * @param {unknown} contentDatPayload
 */
async function outputString(basePath, fromElm, isDevServer, contentDatPayload) {
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

/**
 * @typedef {{ command: "log"; value: any; }} FromElmLog
 *
 * @typedef {{ tag: "ApiResponse" }} FromElmApiResponse
 *
 * @typedef {{ name: string; attributes: string[][]; type: 'head' }} HeadTag
 * @typedef {{ contents: unknown; type: 'json-ld' }} JsonLdTag
 * @typedef {HeadTag | JsonLdTag} SeoTag
 * @typedef {{ head: SeoTag[]; errors: unknown[]; contentJson: string; html: string; route: string; title: string; is404: unknown; statusCode: unknown; headers: unknown[]; }} Arg
 * @typedef {{ tag: "PageProgress"; args: Arg[] }} FromElmPageProgress
 *
 * @typedef {{ oldThing: FromElmNew; binaryPageData: unknown; }} FromElmOldThing
 *
 * @typedef {FromElmLog | FromElmApiResponse | FromElmPageProgress} FromElmNew
 * @typedef {FromElmNew | FromElmOldThing} FromElm
 */

/**
 *
 * @param {unknown} requestHash
 * @param {PortsFile} portsFile
 * @param {string} mode
 * @param {{ url: string; headers: { [x: string]: string; }; method: string; body: import("./request-cache.js").Body; quiet: boolean; }} requestToPerform
 * @returns
 */
async function runHttpJob(requestHash, portsFile, mode, requestToPerform) {
  try {
    const lookupResponse = await lookupOrPerform(
      portsFile,
      mode,
      requestToPerform
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
          rawBytes: lookupResponse.rawBytes || null,
        },
      ];
    } else {
      throw `Unexpected kind ${lookupResponse}`;
    }
  } catch (error) {
    const errorMessage =
      typeof error === "string" ? error : error.message || String(error);

    return [
      requestHash,
      {
        request: requestToPerform,
        response: {
          statusCode: 500,
          statusText: "Internal Error",
          headers: {},
          url: requestToPerform.url,
          bodyKind: "string",
          body: errorMessage,
        },
      },
    ];
  }
}

/**
 * @template R
 * @template J
 * @param {R} request
 * @param {J} json
 * @returns {{ request: R; response: { bodyKind: "json"; body: J; }}}
 */
function jsonResponse(request, json) {
  return {
    request,
    response: { bodyKind: "json", body: json },
  };
}

/**
 * @template B
 * @param {InternalJobWith<string, B>} request
 * @param {Uint8Array | Int32Array} buffer
 * @returns {{ request: InternalJobWith<string, B>; response: { bodyKind: "bytes"; body: null; }; rawBytes: Buffer; }}
 */
function bytesResponse(request, buffer) {
  return {
    request,
    response: {
      bodyKind: "bytes",
      body: null,
    },
    rawBytes: Buffer.from(buffer),
  };
}

/**
 * Convert a Node.js Buffer to a DataView, which is what Lamdera's port
 * system expects for Bytes values.
 */
function bufferToDataView(buf) {
  return new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
}

/**
 * Convert a DataView (received from Lamdera port Bytes) to a Node.js Buffer.
 */
function dataViewToBuffer(dv) {
  return Buffer.from(dv.buffer, dv.byteOffset, dv.byteLength);
}

/**
 * @template U
 * @template A
 * @typedef {{ url: U; body: { args: A }; dir: string[]; quiet: boolean; env: { [key:string]: string; } }} InternalJobWith<U,A>
 */

/**
 * @typedef {InternalJobWith<"elm-pages-internal://log", [{message: string}]>} InternalLogJob
 * @typedef {InternalJobWith<"elm-pages-internal://env", [string]>} InternalEnvJob
 * @typedef {InternalJobWith<"elm-pages-internal://read-file", [unknown, string]>} InternalReadFileJob
 * @typedef {InternalJobWith<"elm-pages-internal://read-file-binary", [unknown, string]>} InternalReadFileBinaryJob
 * @typedef {InternalJobWith<"elm-pages-internal://glob", [{pattern: string; options: { dot: boolean; followSymbolicLinks: boolean; caseSensitiveMatch: boolean; gitIgnore: boolean; deep?: number; onlyFiles: boolean; onlyDirectories: boolean; stats: boolean}}]>} InternalGlobJob
 * @typedef {InternalJobWith<"elm-pages-internal://randomSeed", unknown>} InternalRandomSeedJob
 * @typedef {InternalJobWith<"elm-pages-internal://now", unknown>} InternalNowJob
 * @typedef {InternalJobWith<"elm-pages-internal://encrypt", [{values: unknown; secret: string;}]>} InternalEncryptJob
 * @typedef {InternalJobWith<"elm-pages-internal://decrypt", [{input: string; secrets: string[];}]>} InternalDecryptJob
 * @typedef {InternalJobWith<"elm-pages-internal://write-file", [{path: string; body: string; }]>} InternalWriteFileJob
 * @typedef {InternalJobWith<"elm-pages-internal://sleep", [{milliseconds: number}]>} InternalSleepJob
 * @typedef {InternalJobWith<"elm-pages-internal://which", [string]>} InternalWhichJob
 * @typedef {InternalJobWith<"elm-pages-internal://question", [{prompt: string; }]>} InternalQuestionJob
 * @typedef {InternalJobWith<"elm-pages-internal://readKey", unknown>} InternalReadKeyJob
 * @typedef {InternalJobWith<"elm-pages-internal://stream", [{ kind: string; parts: StreamPart[]}]>} InternalStreamJob
 * @typedef {InternalJobWith<"elm-pages-internal://start-spinner", [{ text: string; immediateStart: boolean; spinnerId?: string; spinner?: string; }]>} InternalStartSpinnerJob
 * @typedef {InternalJobWith<"elm-pages-internal://stop-spinner", [{ spinnerId: string; completionFn: string; completionText: string | null; }]>} InternalStopSpinnerJob
 *
 *
 * @typedef {InternalLogJob | InternalEnvJob | InternalReadFileJob | InternalReadFileBinaryJob | InternalGlobJob | InternalRandomSeedJob | InternalNowJob | InternalEncryptJob | InternalDecryptJob |InternalWriteFileJob | InternalSleepJob| InternalWhichJob | InternalQuestionJob | InternalReadKeyJob | InternalStreamJob | InternalStartSpinnerJob | InternalStopSpinnerJob} InternalJob
 *
 */

/**
 * @param {unknown} requestHash
 * @param {unknown} app
 * @param {Set<string>} patternsToWatch
 * @param {PortsFile} portsFile
 * @param {InternalJob} requestToPerform
 */
async function runInternalJob(
  requestHash,
  app,
  requestToPerform,
  patternsToWatch,
  portsFile
) {
  try {
    switch (requestToPerform.url) {
      case "elm-pages-internal://log":
        return [requestHash, await runLogJob(requestToPerform)];
      case "elm-pages-internal://read-file":
        return [
          requestHash,
          await readFileJobNew(requestToPerform, patternsToWatch),
        ];
      case "elm-pages-internal://read-file-binary":
        return [
          requestHash,
          await readFileBinaryJobNew(requestToPerform, patternsToWatch),
        ];
      case "elm-pages-internal://glob":
        return [
          requestHash,
          await runGlobNew(requestToPerform, patternsToWatch),
        ];
      case "elm-pages-internal://randomSeed":
        return [
          requestHash,
          jsonResponse(
            requestToPerform,
            crypto.getRandomValues(new Uint32Array(1))[0]
          ),
        ];
      case "elm-pages-internal://now":
        return [requestHash, jsonResponse(requestToPerform, Date.now())];
      case "elm-pages-internal://timezone":
        return [requestHash, jsonResponse(requestToPerform, runTimezone(requestToPerform))];
      case "elm-pages-internal://env":
        return [requestHash, await runEnvJob(requestToPerform)];
      case "elm-pages-internal://resolve-path":
        return [requestHash, runResolvePath(requestToPerform)];
      case "elm-pages-internal://encrypt":
        return [requestHash, await runEncryptJob(requestToPerform)];
      case "elm-pages-internal://decrypt":
        return [requestHash, await runDecryptJob(requestToPerform)];
      case "elm-pages-internal://file-exists":
        return [
          requestHash,
          await runFileExists(requestToPerform, patternsToWatch),
        ];
      case "elm-pages-internal://write-file":
        return [requestHash, await runWriteFileJob(requestToPerform)];
      case "elm-pages-internal://delete-file":
        return [requestHash, await runDeleteFile(requestToPerform)];
      case "elm-pages-internal://copy-file":
        return [requestHash, await runCopyFile(requestToPerform)];
      case "elm-pages-internal://move":
        return [requestHash, await runMove(requestToPerform)];
      case "elm-pages-internal://make-directory":
        return [requestHash, await runMakeDirectory(requestToPerform)];
      case "elm-pages-internal://remove-directory":
        return [requestHash, await runRemoveDirectory(requestToPerform)];
      case "elm-pages-internal://make-temp-directory":
        return [requestHash, await runMakeTempDirectory(requestToPerform)];
      case "elm-pages-internal://sleep":
        return [requestHash, await runSleep(requestToPerform)];
      case "elm-pages-internal://which":
        return [requestHash, await runWhich(requestToPerform)];
      case "elm-pages-internal://question":
        return [requestHash, await runQuestion(requestToPerform)];
      case "elm-pages-internal://readKey":
        return [requestHash, await runReadKey(requestToPerform)];
      case "elm-pages-internal://stream":
        return [requestHash, await runStream(requestToPerform, portsFile)];
      case "elm-pages-internal://start-spinner":
        return [requestHash, runStartSpinner(requestToPerform)];
      case "elm-pages-internal://stop-spinner":
        return [requestHash, runStopSpinner(requestToPerform)];
      case "elm-pages-internal://db-read-meta":
        return [requestHash, await runDbReadMeta(requestToPerform)];
      case "elm-pages-internal://db-write":
        return [requestHash, await runDbWrite(requestToPerform)];
      case "elm-pages-internal://db-set-default-path":
        return [requestHash, await runDbSetDefaultPath(requestToPerform)];
      case "elm-pages-internal://db-lock-acquire":
        return [requestHash, await runDbLockAcquire(requestToPerform)];
      case "elm-pages-internal://db-lock-release":
        return [requestHash, await runDbLockRelease(requestToPerform)];
      case "elm-pages-internal://db-migrate-read":
        return [requestHash, await runDbMigrateRead(requestToPerform)];
      case "elm-pages-internal://db-migrate-write":
        return [requestHash, await runDbMigrateWrite(requestToPerform)];
      case "elm-pages-internal://tui-init":
        return [requestHash, await runTuiInit(requestToPerform)];
      case "elm-pages-internal://tui-render":
        return [requestHash, await runTuiRender(requestToPerform)];
      case "elm-pages-internal://tui-wait-event":
        return [requestHash, await runTuiWaitEvent(requestToPerform)];
      case "elm-pages-internal://tui-render-and-wait":
        return [requestHash, await runTuiRenderAndWait(requestToPerform)];
      case "elm-pages-internal://tui-exit":
        return [requestHash, await runTuiExit(requestToPerform)];
      default:
        throw `Unexpected internal BackendTask request format: ${kleur.yellow(
          JSON.stringify(2, null, requestToPerform)
        )}`;
    }
  } catch (error) {
    // Format error message from structured {title, message} or plain strings
    const errorMessage =
      error.title && error.message
        ? `-- ${error.title.toUpperCase()} --\n\n${error.message}`
        : typeof error === "string"
          ? error
          : error.message || String(error);

    // Return a proper [requestHash, response] pair so Object.fromEntries
    // doesn't crash. The non-200 status causes BackendTask.Http to treat
    // this as a BadStatus error, which becomes a FatalError in Elm.
    return [
      requestHash,
      {
        request: requestToPerform,
        response: {
          statusCode: 500,
          statusText: "Internal Error",
          headers: {},
          url: requestToPerform.url,
          bodyKind: "string",
          body: errorMessage,
        },
      },
    ];
  }
}

// --- Database handlers ---

// Track lock tokens per lock file for cleanup on process exit
const dbLockTokensByPath = new Map();
let dbLockCleanupRegistered = false;

function resolveDbBinPath(cwd, payloadOrHeaders) {
  let customPath;
  if (
    payloadOrHeaders &&
    typeof payloadOrHeaders === "object" &&
    typeof payloadOrHeaders.path === "string" &&
    payloadOrHeaders.path.length > 0
  ) {
    // Legacy: path from JSON payload
    customPath = payloadOrHeaders.path;
  } else if (
    typeof payloadOrHeaders === "string" &&
    payloadOrHeaders.length > 0
  ) {
    // New: path passed directly (from x-db-path header)
    customPath = payloadOrHeaders;
  }
  return path.resolve(cwd, customPath || configuredDbPath);
}

/**
 * Extract the x-db-path header value from request headers.
 * Headers are stored as an array of [key, value] pairs.
 */
function getDbPathHeader(req) {
  const entry = req.headers.find(([k]) => k === "x-db-path");
  return entry ? entry[1] : null;
}

function resolveDbLockPath(dbBinPath) {
  return `${dbBinPath}.lock`;
}

/**
 * Remove stale .tmp.{pid} files left behind by previous crashes.
 * Only removes files matching the exact tmp pattern for the given dbBinPath.
 */
async function cleanStaleTmpFiles(dbBinPath) {
  const dir = path.dirname(dbBinPath);
  const base = path.basename(dbBinPath);
  try {
    const entries = await fsPromises.readdir(dir);
    for (const entry of entries) {
      if (entry.startsWith(`${base}.tmp.`)) {
        try {
          await fsPromises.unlink(path.join(dir, entry));
        } catch (_) {}
      }
    }
  } catch (_) {
    // Directory may not exist yet — that's fine
  }
}

function readPositiveIntEnv(name, fallback) {
  const raw = process.env[name];
  if (typeof raw !== "string" || raw.trim() === "") {
    return fallback;
  }

  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

async function runDbSetDefaultPath(req) {
  const payload = req.body.args[0];

  if (
    !payload ||
    typeof payload !== "object" ||
    typeof payload.path !== "string" ||
    payload.path.length === 0
  ) {
    throw {
      title: "Invalid db-set-default-path payload",
      message: "Expected a non-empty path field.",
    };
  }

  configuredDbPath = payload.path;
  return jsonResponse(req, null);
}

async function runDbReadMeta(req) {
  const cwd = path.resolve(...req.dir);
  const payload = req.body.args[0];
  const dbBinPath = resolveDbBinPath(cwd, payload);

  try {
    const fileContents = await fsPromises.readFile(dbBinPath);
    const parsed = parseDbBinHeader(fileContents);
    // [4 bytes version_u32_be][32 bytes hash_raw][4 bytes wire3_length_u32_be][N bytes wire3]
    const hashBytes = Buffer.from(parsed.schemaHashHex, "hex");
    const buf = Buffer.alloc(4 + 32 + 4 + parsed.wire3Data.length);
    buf.writeUInt32BE(parsed.schemaVersion, 0);
    hashBytes.copy(buf, 4);
    buf.writeUInt32BE(parsed.wire3Data.length, 36);
    parsed.wire3Data.copy(buf, 40);
    return bytesResponse(req, buf);
  } catch (error) {
    if (error.code === "ENOENT") {
      // [4 bytes: version=0][32 bytes: zero hash][4 bytes: wire3_length=0]
      return bytesResponse(req, Buffer.alloc(40));
    }
    throw error;
  }
}

async function findCurrentDbElm(cwd) {
  const candidates = [
    path.resolve(cwd, "script/src/Db.elm"),
    path.resolve(cwd, "src/Db.elm"),
  ];

  for (const elmJsonName of ["script/elm.json", "elm.json"]) {
    const elmJsonPath = path.resolve(cwd, elmJsonName);
    try {
      const elmJson = JSON.parse(
        await fsPromises.readFile(elmJsonPath, "utf8")
      );
      const base = path.dirname(elmJsonPath);
      for (const dir of elmJson["source-directories"] || []) {
        candidates.push(path.resolve(base, dir, "Db.elm"));
      }
    } catch (_) {}
  }

  for (const candidate of candidates) {
    try {
      const source = await fsPromises.readFile(candidate, "utf8");
      return { path: candidate, source };
    } catch (_) {}
  }

  return null;
}

async function runDbWrite(req) {
  const cwd = path.resolve(...req.dir);

  // Read raw bytes from port (BytesBody) or fall back to base64 in JSON body
  let wire3Data;
  let schemaHash;
  let dbBinPath;

  if (req.__rawBytes) {
    // New path: raw bytes from port, metadata in headers
    wire3Data = req.__rawBytes;
    const headerEntry = req.headers.find(([k]) => k === "x-schema-hash");
    schemaHash = headerEntry ? headerEntry[1] : null;
    dbBinPath = resolveDbBinPath(cwd, getDbPathHeader(req));
  } else {
    // Legacy path: base64 in JSON body
    const payload = req.body.args[0];
    schemaHash = payload && payload.hash;
    const base64Data = payload && payload.data;
    dbBinPath = resolveDbBinPath(cwd, payload);
    wire3Data =
      typeof base64Data === "string" ? Buffer.from(base64Data, "base64") : null;
  }

  if (typeof schemaHash !== "string" || schemaHash.length === 0 || !wire3Data) {
    throw {
      title: "Invalid db-write payload",
      message: "Expected hash and data fields when writing to the database.",
    };
  }

  // Determine schema version: use current schema version by default.
  // If header hash already matches, preserve existing schema version.
  let schemaVersion = 1;
  try {
    const { readSchemaVersion } = await import("./db-schema.js");
    schemaVersion = await readSchemaVersion(cwd);
  } catch (_) {}

  try {
    const existing = await fsPromises.readFile(dbBinPath);
    const parsed = parseDbBinHeader(existing);
    if (parsed.schemaHashHex === schemaHash) {
      schemaVersion = parsed.schemaVersion;
    }
  } catch (_) {
    // No existing file or unreadable — use current schema version
  }

  // Always write Phase 2 format (auto-upgrades Phase 1 files)
  const fileBuffer = buildDbBin(schemaHash, schemaVersion, wire3Data);

  // Clean up stale tmp files from previous crashes
  await cleanStaleTmpFiles(dbBinPath);

  // Atomic write: write to temp file then rename
  const tmpPath = `${dbBinPath}.tmp.${process.pid}`;
  try {
    await fsPromises.mkdir(path.dirname(dbBinPath), { recursive: true });
    await fsPromises.writeFile(tmpPath, fileBuffer);
    await fsPromises.rename(tmpPath, dbBinPath);
  } catch (error) {
    // Clean up temp file on error
    try {
      await fsPromises.unlink(tmpPath);
    } catch (_) {}
    throw {
      title: "db.bin write failed",
      message: `Failed to write db.bin: ${error.message}`,
    };
  }

  // Best-effort provenance capture: persist Db.elm source for this schema hash.
  try {
    const { saveSchemaSource, computeSchemaHashFromSource } =
      await import("./db-schema.js");
    const currentDb = await findCurrentDbElm(cwd);
    if (currentDb) {
      const currentHash = computeSchemaHashFromSource(currentDb.source);
      if (currentHash === schemaHash) {
        await saveSchemaSource(cwd, schemaHash, currentDb.source);
      }
    }
  } catch (_) {}

  return jsonResponse(req, null);
}

async function runDbLockAcquire(req) {
  const cwd = path.resolve(...req.dir);
  const payload = req.body.args[0];
  const dbBinPath = resolveDbBinPath(cwd, payload);
  const lockPath = resolveDbLockPath(dbBinPath);
  const lockDisplay = path.relative(cwd, lockPath) || lockPath;
  const token = crypto.randomUUID();
  const lockData = JSON.stringify({
    pid: process.pid,
    createdAt: new Date().toISOString(),
    token,
  });

  const lockWaitTimeoutMs = readPositiveIntEnv(
    "ELM_PAGES_DB_LOCK_TIMEOUT_MS",
    60000
  );
  const staleTimeoutMs = readPositiveIntEnv(
    "ELM_PAGES_DB_STALE_LOCK_TIMEOUT_MS",
    5 * 60 * 1000
  );
  const minRetryDelayMs = readPositiveIntEnv("ELM_PAGES_DB_LOCK_RETRY_MS", 50);
  const maxRetryDelayMs = readPositiveIntEnv(
    "ELM_PAGES_DB_LOCK_MAX_RETRY_MS",
    500
  );
  const lockWaitDeadline = Date.now() + lockWaitTimeoutMs;
  let attempt = 0;

  await fsPromises.mkdir(path.dirname(lockPath), { recursive: true });

  while (Date.now() < lockWaitDeadline) {
    try {
      // Exclusive create - fails if file exists
      await fsPromises.writeFile(lockPath, lockData, { flag: "wx" });

      // Lock acquired
      dbLockTokensByPath.set(lockPath, token);

      // Register process exit cleanup (once)
      if (!dbLockCleanupRegistered) {
        dbLockCleanupRegistered = true;
        process.on("exit", () => {
          for (const [cleanupLockPath, cleanupToken] of dbLockTokensByPath) {
            try {
              const existing = JSON.parse(
                fs.readFileSync(cleanupLockPath, "utf8")
              );
              if (existing.token === cleanupToken) {
                fs.unlinkSync(cleanupLockPath);
              }
            } catch (_) {}
          }
          dbLockTokensByPath.clear();
        });
      }

      return jsonResponse(req, token);
    } catch (error) {
      if (error.code !== "EEXIST") {
        throw {
          title: "Database lock error",
          message: `Failed to create lock file ${lockDisplay}: ${error.message}`,
        };
      }

      // Lock file exists - check if stale
      try {
        const existingLock = JSON.parse(
          await fsPromises.readFile(lockPath, "utf8")
        );

        // Check if the PID is still alive
        let pidAlive = false;
        try {
          process.kill(existingLock.pid, 0);
          pidAlive = true;
        } catch (_) {
          pidAlive = false;
        }

        // Check if lock is older than stale timeout
        const lockAge = Date.now() - new Date(existingLock.createdAt).getTime();

        if (!pidAlive || lockAge > staleTimeoutMs) {
          // Stale lock - remove and retry
          await fsPromises.unlink(lockPath);
          continue;
        }

        // Lock is held by a live process - wait with bounded backoff + jitter
        const exponentialMs = Math.min(
          maxRetryDelayMs,
          minRetryDelayMs * 2 ** Math.min(attempt, 5)
        );
        const jitterMs = Math.floor(
          Math.random() * Math.max(1, minRetryDelayMs)
        );
        await new Promise((resolve) =>
          setTimeout(resolve, exponentialMs + jitterMs)
        );
        attempt++;
      } catch (readError) {
        if (readError.code === "ENOENT") {
          // Lock file disappeared between check and read - retry immediately
          continue;
        }
        // Corrupted lock file (e.g. invalid JSON) - remove and retry
        try {
          await fsPromises.unlink(lockPath);
        } catch (_) {}
        continue;
      }
    }
  }

  const timeoutSeconds = Math.ceil(lockWaitTimeoutMs / 1000);
  throw {
    title: "Database locked",
    message: `The database lock ${lockDisplay} is still held by another process after ${timeoutSeconds}s. If you believe this lock is stale, delete ${lockDisplay} and try again.`,
  };
}

async function runDbLockRelease(req) {
  const cwd = path.resolve(...req.dir);
  const payload = req.body.args[0];
  const token =
    typeof payload === "string" ? payload : payload && payload.token;
  const dbBinPath =
    typeof payload === "string"
      ? resolveDbBinPath(cwd, null)
      : resolveDbBinPath(cwd, payload);
  const lockPath = resolveDbLockPath(dbBinPath);

  if (typeof token !== "string" || token.length === 0) {
    throw {
      title: "Invalid db-lock-release payload",
      message: "Expected token when releasing database lock.",
    };
  }

  try {
    const existing = JSON.parse(await fsPromises.readFile(lockPath, "utf8"));
    if (existing.token === token) {
      await fsPromises.unlink(lockPath);
      dbLockTokensByPath.delete(lockPath);
    }
  } catch (_) {
    // Lock file already gone - that's fine
  }

  return jsonResponse(req, null);
}

async function runDbMigrateRead(req) {
  const cwd = path.resolve(...req.dir);
  const payload = req.body.args[0];
  const dbBinPath = resolveDbBinPath(cwd, payload);

  try {
    const fileContents = await fsPromises.readFile(dbBinPath);
    const parsed = parseDbBinHeader(fileContents);
    // [4 bytes version_u32_be][4 bytes wire3_length_u32_be][N bytes wire3]
    const buf = Buffer.alloc(4 + 4 + parsed.wire3Data.length);
    buf.writeUInt32BE(parsed.schemaVersion, 0);
    buf.writeUInt32BE(parsed.wire3Data.length, 4);
    parsed.wire3Data.copy(buf, 8);
    return bytesResponse(req, buf);
  } catch (error) {
    if (error.code === "ENOENT") {
      // [4 bytes: version=0][4 bytes: wire3_length=0]
      return bytesResponse(req, Buffer.alloc(8));
    }
    throw error;
  }
}

async function runDbMigrateWrite(req) {
  const cwd = path.resolve(...req.dir);

  // Read raw bytes from port (BytesBody) or fall back to base64 in JSON body
  let wire3Data;
  let dbBinPath;

  if (req.__rawBytes) {
    // New path: raw bytes from port, path in headers
    wire3Data = req.__rawBytes;
    dbBinPath = resolveDbBinPath(cwd, getDbPathHeader(req));
  } else {
    // Legacy path: base64 in JSON body
    const payload = req.body.args[0];
    const base64Data = payload && payload.data;
    dbBinPath = resolveDbBinPath(cwd, payload);
    wire3Data =
      typeof base64Data === "string" ? Buffer.from(base64Data, "base64") : null;
  }

  if (!wire3Data) {
    throw {
      title: "Invalid db-migrate-write payload",
      message: "Expected data field when writing migrated database data.",
    };
  }

  // Read current schema hash from the current Db.elm source
  // The migration chain encodes with the NEW Db.w3_encode_Db,
  // so we need the current schema hash for the new db.bin header.
  const { readSchemaVersion, saveSchemaSource, computeSchemaHashFromSource } =
    await import("./db-schema.js");

  const schemaVersion = await readSchemaVersion(cwd);

  // Compute hash from current Db.elm
  let schemaHash;
  try {
    const currentDb = await findCurrentDbElm(cwd);
    if (!currentDb) {
      throw {
        title: "Migration write failed",
        message: "Could not find Db.elm to compute schema hash.",
      };
    }
    schemaHash = computeSchemaHashFromSource(currentDb.source);
    await saveSchemaSource(cwd, schemaHash, currentDb.source);
  } catch (error) {
    if (error.title) throw error;
    throw {
      title: "Migration write failed",
      message: `Error computing schema hash: ${error.message}`,
    };
  }

  // Create backup before writing
  try {
    await fsPromises.copyFile(dbBinPath, `${dbBinPath}.backup`);
  } catch (_) {
    // No existing file to back up — that's fine
  }

  const fileBuffer = buildDbBin(schemaHash, schemaVersion, wire3Data);

  // Clean up stale tmp files from previous crashes
  await cleanStaleTmpFiles(dbBinPath);

  // Atomic write
  const tmpPath = `${dbBinPath}.tmp.${process.pid}`;
  try {
    await fsPromises.mkdir(path.dirname(dbBinPath), { recursive: true });
    await fsPromises.writeFile(tmpPath, fileBuffer);
    await fsPromises.rename(tmpPath, dbBinPath);
  } catch (error) {
    try {
      await fsPromises.unlink(tmpPath);
    } catch (_) {}
    throw {
      title: "Migration write failed",
      message: `Failed to write db.bin: ${error.message}`,
    };
  }

  return jsonResponse(req, null);
}

/**
 * @param {InternalJobWith<string, unknown>} requestToPerform
 * @returns {{ cwd: string; quiet: boolean; env: NodeJS.ProcessEnv}}
 */
function getContext(requestToPerform) {
  const cwd = path.resolve(...requestToPerform.dir);
  const quiet = requestToPerform.quiet;
  const env = { ...process.env, ...requestToPerform.env };

  return { cwd, quiet, env };
}
/**
 *
 * @param {InternalReadFileJob} req
 * @param {Set<string>} patternsToWatch
 * @returns
 */
async function readFileJobNew(req, patternsToWatch) {
  const cwd = path.resolve(...req.dir);
  // TODO use cwd
  const filePath = path.resolve(cwd, req.body.args[1]);
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

/**
 * @param {InternalReadFileBinaryJob} req
 * @param {Set<string>} patternsToWatch
 */
async function readFileBinaryJobNew(req, patternsToWatch) {
  const filePath = req.body.args[1];
  try {
    patternsToWatch.add(filePath);

    const fileContents = await fsPromises.readFile(filePath);
    // It's safe to use allocUnsafe here because we're going to overwrite it immediately anyway
    const buffer = new Uint8Array(4 + fileContents.length);
    const view = new DataView(
      buffer.buffer,
      buffer.byteOffset,
      buffer.byteLength
    );
    view.setInt32(0, fileContents.length);
    fileContents.copy(buffer, 4);

    return bytesResponse(req, buffer);
  } catch (error) {
    const buffer = new Int32Array(1);
    buffer[0] = -1;
    return bytesResponse(req, buffer);
  }
}

/**
 * @param {InternalSleepJob} req
 */
function runSleep(req) {
  const { milliseconds } = req.body.args[0];
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve(jsonResponse(req, null));
    }, milliseconds);
  });
}

/**
 * @param {InternalWhichJob} req
 */
async function runWhich(req) {
  const command = req.body.args[0];
  try {
    return jsonResponse(req, await which(command));
  } catch (error) {
    return jsonResponse(req, null);
  }
}

/**
 * @param {InternalQuestionJob} req
 */
async function runQuestion(req) {
  return jsonResponse(req, await question(req.body.args[0].prompt));
}

/**
 * @param {InternalReadKeyJob} req
 */
async function runReadKey(req) {
  return jsonResponse(req, await readKey());
}

/**
 * @param {InternalStreamJob} req
 * @param {PortsFile} portsFile
 */
function runStream(req, portsFile) {
  return new Promise(async (resolve) => {
    const context = getContext(req);
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
          (value) => resolve(jsonResponse(req, value)),
          isLastProcess,
          kind
        );
        metadataResponse = metadata;
        thisStream = stream;

        lastStream = thisStream;
        index += 1;
      }
      if (kind === "json") {
        try {
          const body = await consumers.json(lastStream);
          const metadata = await tryCallingFunction(metadataResponse);
          resolve(jsonResponse(req, { body, metadata }));
        } catch (error) {
          resolve(jsonResponse(req, { error: error.toString() }));
        }
      } else if (kind === "text") {
        try {
          const body = await consumers.text(lastStream);
          const metadata = await tryCallingFunction(metadataResponse);
          resolve(jsonResponse(req, { body, metadata }));
        } catch (error) {
          resolve(jsonResponse(req, { error: error.toString() }));
        }
      } else if (kind === "none") {
        if (!lastStream) {
          // ensure all error handling gets a chance to fire before resolving successfully
          await tryCallingFunction(metadataResponse);
          resolve(jsonResponse(req, { body: null }));
        } else {
          let resolvedMeta = await tryCallingFunction(metadataResponse);
          // Writable streams emit "finish", Readable streams emit "end"
          // Duplex streams emit both - use a flag to prevent double-resolve
          let resolved = false;
          const onComplete = () => {
            if (resolved) return;
            resolved = true;
            resolve(
              jsonResponse(req, {
                body: null,
                metadata: resolvedMeta,
              })
            );
          };
          lastStream.once("finish", onComplete);
          lastStream.once("end", onComplete);
        }
      } else if (kind === "command") {
        // already handled in parts.forEach
      }
    } catch (error) {
      if (lastStream) {
        lastStream.destroy();
      }

      resolve(jsonResponse(req, { error: error.toString() }));
    }
  });
}

/**
 * @typedef {StreamPartWith<"unzip", {}> | StreamPartWith<"gzip", {}> | StreamPartWith<"stdin", {}> | StreamPartWith<"stdout", {}> | StreamPartWith<"stderr", {}> | FromStringPart | CommandPart | HttpWritePart | FileReadPart | FileWritePart | CustomReadPart | CustomWritePart | CustomDuplexPart} StreamPart
 *
 * @typedef {StreamPartWith<"fromString", { string: string; }>} FromStringPart
 * @typedef {StreamPartWith<"command", { command: string; args: string[]; allowNon0Status: boolean; output: "Ignore" | "Print" | "MergeWithStdout" | "InsteadOfStdout"; timeoutInMs: number?; }>} CommandPart
 * @typedef {StreamPartWith<"httpWrite", { url: string; method: string; headers: { key: string; value: string; }[]; body?: StaticHttpBody; retries: number?; timeoutInMs: number?; }>} HttpWritePart
 * @typedef {StreamPartWith<"fileRead", { path: string; }>} FileReadPart
 * @typedef {StreamPartWith<"fileWrite", { path: string; }>} FileWritePart
 * @typedef {StreamPartWith<"customRead", { portName: string; input: unknown; }>} CustomReadPart
 * @typedef {StreamPartWith<"customWrite", { portName: string; input: unknown; }>} CustomWritePart
 * @typedef {StreamPartWith<"customDuplex", { portName: string; input: unknown; }>} CustomDuplexPart
 */

/**
 * @template Key
 * @typedef {{ name: Key; }} SimpleStreamPart<Key>
 */

/**
 * @template Key
 * @template Values
 * @typedef {{ name: Key; } & Values} StreamPartWith<Key,Values>
 */

/**
 * @param {?import('node:stream').Stream} lastStream
 * @param {StreamPart} part
 * @param {{ cwd: string; quiet: boolean; env: NodeJS.ProcessEnv; }} param2
 * @param {PortsFile} portsFile
 * @param {((value: unknown) => void) | ((arg0: { error: unknown; }) => void) } resolve
 * @param {boolean} isLastProcess
 * @param {string} kind
 * @returns {Promise<{ stream: import('node:stream').Stream; metadata?: Promise<unknown> | (() => unknown); }>}
 */
async function pipePartToStream(
  lastStream,
  part,
  { cwd, quiet, env },
  portsFile,
  resolve,
  isLastProcess,
  kind
) {
  if (verbosity > 1 && !quiet) {
  }
  if (part.name === "stdout") {
    return { stream: pipeIfPossible(lastStream, stdout()) };
  } else if (part.name === "stderr") {
    return { stream: pipeIfPossible(lastStream, stderr()) };
  } else if (part.name === "stdin") {
    return { stream: process.stdin };
  } else if (part.name === "fileRead") {
    const newLocal = fs.createReadStream(path.resolve(cwd, part.path));
    newLocal.once("error", (error) => {
      newLocal.close();
      resolve({ error: error.toString() });
    });
    return { stream: newLocal };
  } else if (part.name === "customDuplex") {
    const newLocal = await portsFile[part.portName](part.input, {
      cwd,
      quiet,
      env,
    });
    if (validateStream.isDuplexStream(newLocal.stream)) {
      newLocal.stream.once("error", (error) => {
        newLocal.stream.destroy();
        resolve({
          error: `Custom duplex stream '${part.portName}' error: ${error.message}`,
        });
      });
      pipeIfPossible(lastStream, newLocal.stream);
      if (!lastStream) {
        endStreamIfNoInput(newLocal.stream);
      }
      return newLocal;
    } else {
      throw `Expected '${part.portName}' to be a duplex stream!`;
    }
  } else if (part.name === "customRead") {
    const newLocal = await portsFile[part.portName](part.input, {
      cwd,
      quiet,
      env,
    });
    // customRead can return either a stream directly or { stream, metadata }
    const stream = newLocal.stream || newLocal;
    if (!validateStream.isReadableStream(stream)) {
      throw `Expected '${part.portName}' to return a readable stream!`;
    }
    stream.once("error", (error) => {
      stream.destroy();
      resolve({
        error: `Custom read stream '${part.portName}' error: ${error.message}`,
      });
    });
    return {
      metadata: newLocal.metadata || null,
      stream: stream,
    };
  } else if (part.name === "customWrite") {
    const newLocal = await portsFile[part.portName](part.input, {
      cwd,
      quiet,
      env,
    });
    if (!validateStream.isWritableStream(newLocal.stream)) {
      throw `Expected '${part.portName}' to return a writable stream!`;
    }
    newLocal.stream.once("error", (error) => {
      newLocal.stream.destroy();
      resolve({
        error: `Custom write stream '${part.portName}' error: ${error.message}`,
      });
    });
    pipeIfPossible(lastStream, newLocal.stream);
    if (!lastStream) {
      endStreamIfNoInput(newLocal.stream);
    }
    return newLocal;
  } else if (part.name === "gzip") {
    const gzip = zlib.createGzip();
    gzip.once("error", (error) => {
      gzip.destroy();
      resolve({ error: `gzip error: ${error.message}` });
    });
    if (!lastStream) {
      endStreamIfNoInput(gzip);
    }
    return {
      stream: pipeIfPossible(lastStream, gzip),
    };
  } else if (part.name === "unzip") {
    const unzip = zlib.createUnzip();
    unzip.once("error", (error) => {
      unzip.destroy();
      resolve({ error: `unzip error: ${error.message}` });
    });
    if (!lastStream) {
      endStreamIfNoInput(unzip);
    }
    return {
      stream: pipeIfPossible(lastStream, unzip),
    };
  } else if (part.name === "fileWrite") {
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
    pipeIfPossible(lastStream, newLocal);
    if (!lastStream) {
      endStreamIfNoInput(newLocal);
    }
    return {
      stream: newLocal,
    };
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
  } else if (part.name === "command") {
    const { command, args, allowNon0Status, output } = part;
    /** @type {'ignore' | 'inherit'} } */
    let letPrint = quiet ? "ignore" : "inherit";
    /** @type {'ignore' | 'inherit' | 'pipe'} } */
    let stderrKind = kind === "none" && isLastProcess ? letPrint : "pipe";
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
    if (!lastStream) {
      endStreamIfNoInput(newProcess.stdin);
    }
    let newStream;
    if (output === "MergeWithStdout") {
      newStream = mergeStreams([newProcess.stdout, newProcess.stderr]);
    } else if (output === "InsteadOfStdout") {
      newStream = newProcess.stderr;
    } else {
      newStream = newProcess.stdout;
    }

    if (isLastProcess) {
      // For the last process, we need to track metadata resolution
      // so we can resolve it even if the process errors
      /** @type {((value: ({ exitCode: null; error: string} | { exitCode : number | null; })) => void)} */
      let resolveMeta;

      const metadataPromise = new Promise((resolve) => {
        resolveMeta = resolve;
      });

      newProcess.once("error", (error) => {
        newStream && newStream.end();
        newProcess.removeAllListeners();
        // Resolve metadata Promise to prevent hanging awaits
        if (resolveMeta) {
          resolveMeta({ exitCode: null, error: error.toString() });
        }
        resolve({ error: error.toString() });
      });

      newProcess.once("exit", (code) => {
        if (code !== 0 && !allowNon0Status) {
          newStream && newStream.end();
          resolve({
            error: `Command ${command} exited with code ${code}`,
          });
        }
        resolveMeta({
          exitCode: code,
        });
      });
      return {
        stream: newStream,
        metadata: metadataPromise,
      };
    } else {
      newProcess.once("error", (error) => {
        newStream && newStream.end();
        newProcess.removeAllListeners();
        resolve({ error: error.toString() });
      });

      return { stream: newStream };
    }
  } else if (part.name === "fromString") {
    return { stream: Readable.from([part.string]) };
  } else {
    // console.error(`Unknown stream part: ${part.name}!`);
    // process.exit(1);
    throw `Unknown stream part: ${part.name}!`;
  }
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

/**
 * Safely signals EOF to a writable stream when no input will be piped to it.
 *
 * This is necessary because when a writable stream (like a child process's stdin)
 * is created but nothing is piped to it, the receiving end has no way to know
 * that no data is coming. It will wait indefinitely for the pipe to close.
 *
 * GUI applications like ksdiff/meld are particularly affected - they wait for
 * stdin to close before proceeding, causing hangs if we don't explicitly end it.
 *
 * @param {import('stream').Writable | null | undefined} stream - The writable stream to end
 */
function endStreamIfNoInput(stream) {
  if (!stream) {
    return;
  }

  // Check if stream is still in a state where .end() is valid
  // - writable: false if the stream has been destroyed or ended
  // - writableEnded: true if .end() has already been called
  // - destroyed: true if .destroy() has been called
  if (!stream.writable || stream.writableEnded || stream.destroyed) {
    return;
  }

  // Add a one-time error handler to prevent unhandled error crashes
  // This can happen if the child process exits before we call .end()
  stream.once("error", (err) => {
    // EPIPE: "broken pipe" - the other end closed before we finished
    // This is expected if the child process exits quickly
    if (err.code !== "EPIPE") {
      // Log unexpected errors but don't crash - this is cleanup code
      console.error("Stream end error:", err.message);
    }
  });

  stream.end();
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

/**
 * @template T
 * @param {Promise<T> | (() => Promise<T>) | null | undefined} func
 * @return {Promise<T | null | undefined>}
 */
async function tryCallingFunction(func) {
  if (func) {
    // if is function
    if (typeof func === "function") {
      return await func();
    }
    // if is promise
    else {
      return await func;
    }
  } else {
    return func;
  }
}

/**
 * @param {string} prompt
 * @returns {Promise<string>}
 */
export async function question(prompt) {
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

/**
 * Read a single keypress from stdin without requiring Enter.
 * Uses raw mode to capture individual keypresses.
 * Falls back to line-buffered input when not in a TTY (e.g., piped input).
 */
export async function readKey() {
  const stdin = process.stdin;

  if (!stdin.isTTY) {
    // Fall back to reading a line when not in a TTY (piped input, CI, etc.)
    // Takes the first character of the input line
    const rl = readline.createInterface({ input: stdin });
    return new Promise((resolve) => {
      rl.once("line", (line) => {
        rl.close();
        resolve(line.charAt(0) || "\n");
      });
    });
  }

  // TTY mode - single keypress without Enter
  return new Promise((resolve) => {
    const wasRaw = stdin.isRaw;

    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding("utf8");

    stdin.once("data", (key) => {
      stdin.setRawMode(wasRaw);
      stdin.pause();

      // Handle Ctrl+C to exit gracefully
      if (key === "\u0003") {
        process.exit();
      }

      resolve(key);
    });
  });
}

async function runFileExists(req, patternsToWatch) {
  const cwd = path.resolve(...req.dir);
  const filePath = path.resolve(cwd, req.body.args[0]);
  patternsToWatch.add(filePath);
  try {
    await fsPromises.access(filePath, fs.constants.F_OK);
    return jsonResponse(req, true);
  } catch {
    return jsonResponse(req, false);
  }
}

async function runDeleteFile(req) {
  const cwd = path.resolve(...req.dir);
  const data = req.body.args[0];
  const filePath = path.resolve(cwd, data.path);
  try {
    await fsPromises.unlink(filePath);
    return jsonResponse(req, null);
  } catch (error) {
    if (error.code === "ENOENT") {
      return jsonResponse(req, null);
    }
    throw {
      title: "BackendTask Error",
      message: `Script.removeFile failed for path: ${kleur.yellow(
        filePath
      )}\n${kleur.red(error.toString())}`,
    };
  }
}

async function runCopyFile(req) {
  const cwd = path.resolve(...req.dir);
  const data = req.body.args[0];
  const fromPath = path.resolve(cwd, data.from);
  const toPath = path.resolve(cwd, data.to);
  try {
    await fsPromises.mkdir(path.dirname(toPath), { recursive: true });
    await fsPromises.copyFile(fromPath, toPath);
    return jsonResponse(req, toPath);
  } catch (error) {
    throw {
      title: "BackendTask Error",
      message: `Script.copyFile failed from ${kleur.yellow(
        fromPath
      )} to ${kleur.yellow(toPath)}\n${kleur.red(error.toString())}`,
    };
  }
}

async function runMove(req) {
  const cwd = path.resolve(...req.dir);
  const data = req.body.args[0];
  const fromPath = path.resolve(cwd, data.from);
  const toPath = path.resolve(cwd, data.to);
  try {
    await fsPromises.mkdir(path.dirname(toPath), { recursive: true });
    await fsPromises.rename(fromPath, toPath);
    return jsonResponse(req, toPath);
  } catch (error) {
    if (error.code === "EXDEV") {
      try {
        const stat = await fsPromises.lstat(fromPath);
        await fsPromises.mkdir(path.dirname(toPath), { recursive: true });

        if (stat.isDirectory()) {
          await fsPromises.cp(fromPath, toPath, { recursive: true });
        } else {
          await fsPromises.copyFile(fromPath, toPath);
        }

        await fsPromises.rm(fromPath, { recursive: true });
        return jsonResponse(req, toPath);
      } catch (crossDeviceError) {
        throw {
          title: "BackendTask Error",
          message: `Script.move failed from ${kleur.yellow(
            fromPath
          )} to ${kleur.yellow(toPath)}\n${kleur.red(crossDeviceError.toString())}`,
        };
      }
    }

    throw {
      title: "BackendTask Error",
      message: `Script.move failed from ${kleur.yellow(
        fromPath
      )} to ${kleur.yellow(toPath)}\n${kleur.red(error.toString())}`,
    };
  }
}

async function runMakeDirectory(req) {
  const cwd = path.resolve(...req.dir);
  const data = req.body.args[0];
  const dirPath = path.resolve(cwd, data.path);
  try {
    await fsPromises.mkdir(dirPath, { recursive: data.recursive });
    return jsonResponse(req, dirPath);
  } catch (error) {
    throw {
      title: "BackendTask Error",
      message: `Script.makeDirectory failed for path: ${kleur.yellow(
        dirPath
      )}\n${kleur.red(error.toString())}`,
    };
  }
}

async function runRemoveDirectory(req) {
  const cwd = path.resolve(...req.dir);
  const data = req.body.args[0];
  const dirPath = path.resolve(cwd, data.path);
  try {
    const stat = await fsPromises.lstat(dirPath);
    if (!stat.isDirectory()) {
      throw {
        code: "ENOTDIR",
        toString: () => `Not a directory: ${dirPath}`,
      };
    }

    if (data.recursive) {
      await fsPromises.rm(dirPath, { recursive: true });
    } else {
      await fsPromises.rmdir(dirPath);
    }
    return jsonResponse(req, null);
  } catch (error) {
    if (error.code === "ENOENT") {
      return jsonResponse(req, null);
    }
    throw {
      title: "BackendTask Error",
      message: `Script.removeDirectory failed for path: ${kleur.yellow(
        dirPath
      )}\n${kleur.red(error.toString())}`,
    };
  }
}

async function runMakeTempDirectory(req) {
  const prefix = req.body.args[0];
  try {
    const tmpDir = await fsPromises.mkdtemp(path.join(os.tmpdir(), prefix));
    return jsonResponse(req, tmpDir);
  } catch (error) {
    throw {
      title: "BackendTask Error",
      message: `Script.makeTempDirectory failed with prefix: ${kleur.yellow(
        prefix
      )}\n${kleur.red(error.toString())}`,
    };
  }
}

/**
 * @param {InternalWriteFileJob} req
 */
async function runWriteFileJob(req) {
  const cwd = path.resolve(...req.dir);
  const data = req.body.args[0];
  const filePath = path.resolve(cwd, data.path);
  try {
    await fsPromises.mkdir(path.dirname(filePath), { recursive: true });
    await fsPromises.writeFile(filePath, data.body);
    return jsonResponse(req, filePath);
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

/**
 * @param {InternalStartSpinnerJob} req
 */
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

/**
 * @param {InternalStopSpinnerJob} req
 */
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

/**
 * @param {InternalGlobJob} req
 * @param {Set<string>} patternsToWatch
 */
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
          captures: mm.capture(pattern, fullPath.path) || [],
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

/**
 * @param {InternalLogJob} req
 */
async function runLogJob(req) {
  try {
    console.log(req.body.args[0].message);
    return jsonResponse(req, null);
  } catch (e) {
    console.log(`Error performing log '${JSON.stringify(req.body)}'`);
    throw e;
  }
}

function runResolvePath(req) {
  const filePath = req.body.args[0];
  const cwd = path.resolve(...req.dir);
  const resolvedPath = path.resolve(cwd, filePath);
  return jsonResponse(req, resolvedPath);
}

/**
 * @param {InternalEnvJob} req
 */
async function runEnvJob(req) {
  try {
    const expectedEnv = req.body.args[0];
    return jsonResponse(req, expectedEnv in req.env ? req.env[expectedEnv] : process.env[expectedEnv] || null);
  } catch (e) {
    console.log(`Error performing env '${JSON.stringify(req.body)}'`);
    throw e;
  }
}

/**
 * @param {InternalEncryptJob} req
 */
async function runEncryptJob(req) {
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
      message: e.toString() + e.stack + "\n\n" + JSON.stringify(req, null, 2),
    };
  }
}

/**
 * @param {InternalDecryptJob} req
 */
async function runDecryptJob(req) {
  try {
    // TODO if tryDecodeCookie returns `null`, need to have an `Err` in Elm because decryption failed
    const signed = tryDecodeCookie(
      req.body.args[0].input,
      req.body.args[0].secrets
    );

    return jsonResponse(req, JSON.parse(signed || "null"));
  } catch (e) {
    throw {
      title: "BackendTask Decrypt Error",
      message: e.toString() + e.stack + "\n\n" + JSON.stringify(req, null, 2),
    };
  }
}

/**
 * @param {{ ports: { fromJsPort: { send: (arg0: { tag: string; data: unknown; }) => void; }; }; }} app
 * @param {{ message: string; title: string; }} error
 */
function sendError(app, error) {
  foundErrors = true;

  app.ports.fromJsPort.send({
    tag: "BuildError",
    data: error,
  });
}

/**
 * @param {string} input
 * @param {crypto.CipherKey[]} secrets
 * @returns {string | null}
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

// --- Timezone helpers ---

const TWO_WEEKS_MS = 14 * 24 * 60 * 60 * 1000;

/**
 * Handle elm-pages-internal://timezone requests.
 * Accepts { sinceMs, untilMs } for the date range to scan for DST transitions.
 * Optionally accepts { tzId } for a named timezone; defaults to system timezone.
 * Returns { defaultOffset, eras } for Time.customZone.
 */
function runTimezone(req) {
  const body = req.body.args[0];
  const tzId = body.tzId || Intl.DateTimeFormat().resolvedOptions().timeZone;

  // Validate timezone name by attempting a format
  try {
    Intl.DateTimeFormat("en-US", { timeZone: tzId });
  } catch (e) {
    throw {
      title: "Invalid Timezone",
      message: `"${tzId}" is not a valid IANA timezone identifier.\n\nExamples of valid identifiers: "America/New_York", "Europe/London", "Asia/Tokyo", "UTC".`,
    };
  }

  const { sinceMs, untilMs } = body;

  if (typeof globalThis.Temporal !== "undefined") {
    return getTimezoneDataTemporal(tzId, sinceMs, untilMs);
  }
  return getTimezoneDataIntl(tzId, sinceMs, untilMs);
}

/**
 * Cache Intl.DateTimeFormat instances for performance.
 * Using formatToParts + cached formatters is ~10x faster than toLocaleString re-parsing.
 */
const tzFormatters = new Map();
const utcFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: "UTC",
  year: "numeric", month: "numeric", day: "numeric",
  hour: "numeric", minute: "numeric", second: "numeric",
  hour12: false,
});

function getTzFormatter(tzId) {
  let fmt = tzFormatters.get(tzId);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat("en-US", {
      timeZone: tzId,
      year: "numeric", month: "numeric", day: "numeric",
      hour: "numeric", minute: "numeric", second: "numeric",
      hour12: false,
    });
    tzFormatters.set(tzId, fmt);
  }
  return fmt;
}

function partsToMs(parts) {
  const p = {};
  for (const { type, value } of parts) p[type] = parseInt(value) || 0;
  const h = p.hour === 24 ? 0 : p.hour;
  return Date.UTC(p.year, p.month - 1, p.day, h, p.minute, p.second);
}

/**
 * Get UTC offset in minutes for a timezone at a given instant.
 */
function getOffsetMinutesIntl(tzId, ms) {
  const utcMs = partsToMs(utcFormatter.formatToParts(ms));
  const localMs = partsToMs(getTzFormatter(tzId).formatToParts(ms));
  return (localMs - utcMs) / 60000;
}

/**
 * Binary search to find the exact minute when a timezone offset transition occurs.
 */
function binarySearchTransition(tzId, loMs, hiMs, offsetBefore) {
  while (hiMs - loMs > 60000) {
    const mid = Math.floor((loMs + hiMs) / 2);
    if (getOffsetMinutesIntl(tzId, mid) === offsetBefore) {
      loMs = mid;
    } else {
      hiMs = mid;
    }
  }
  return hiMs;
}

/**
 * Get timezone transition data using the Intl API (scan + binary search).
 * Scans every 2 weeks to catch even rare mid-month transitions.
 */
function getTimezoneDataIntl(tzId, sinceMs, untilMs) {
  const defaultOffset = getOffsetMinutesIntl(tzId, sinceMs);
  const eras = [];
  let prevOffset = defaultOffset;

  let scanMs = sinceMs + TWO_WEEKS_MS;
  while (scanMs <= untilMs) {
    const offset = getOffsetMinutesIntl(tzId, scanMs);
    if (offset !== prevOffset) {
      const exactMs = binarySearchTransition(
        tzId,
        scanMs - TWO_WEEKS_MS,
        scanMs,
        prevOffset
      );
      eras.push({
        start: Math.floor(exactMs / 60000),
        offset: offset,
      });
      prevOffset = offset;
    }
    scanMs += TWO_WEEKS_MS;
  }

  // elm/time expects eras sorted newest-first
  eras.reverse();
  return { defaultOffset, eras };
}

/**
 * Get timezone transition data using the Temporal API (direct transition walking).
 */
function getTimezoneDataTemporal(tzId, sinceMs, untilMs) {
  const Temporal = globalThis.Temporal;
  const tz = Temporal.TimeZone.from(tzId);
  const startInstant = Temporal.Instant.fromEpochMilliseconds(sinceMs);
  const endInstant = Temporal.Instant.fromEpochMilliseconds(untilMs);

  const defaultOffset = tz.getOffsetNanosecondsFor(startInstant) / 60_000_000_000;
  const eras = [];

  let instant = tz.getNextTransition(startInstant);
  while (instant && Temporal.Instant.compare(instant, endInstant) < 0) {
    const offsetMinutes = tz.getOffsetNanosecondsFor(instant) / 60_000_000_000;
    eras.push({
      start: Math.floor(instant.epochMilliseconds / 60000),
      offset: offsetMinutes,
    });
    instant = tz.getNextTransition(instant);
  }

  // elm/time expects eras sorted newest-first
  eras.reverse();
  return { defaultOffset, eras };
}

// ── TUI Runtime ──────────────────────────────────────────────────────────────

let tuiColorProfile = null; // detected once at init: 'truecolor' | '256' | '16' | 'mono'
let tuiActive = false;
// Scroll bounce suppression: macOS rubber-band effect sends reverse scroll
// events when hitting a boundary. The Magic Trackpad's aggressive momentum
// makes this especially visible. Track recent scroll direction + timestamp
// to suppress bounce-back events within a short window.
let tuiLastScrollDir = null; // 'scrollUp' | 'scrollDown' | null
let tuiLastScrollTime = 0;
let tuiTickTimer = null; // setInterval ID for tick events
let tuiTickInterval = null; // current tick interval in ms
let tuiEventQueue = []; // events that arrived during Elm processing
let tuiEventResolve = null; // pending promise resolver for next wait
let tuiStdinLeftover = ""; // partial escape sequence carried across data chunks
let tuiDebugLog = null; // file descriptor for debug logging
let tuiLastRenderTime = 0; // timestamp of last actual terminal write
let tuiPendingRender = null; // deferred render to ensure final frame is shown
const TUI_MIN_RENDER_INTERVAL = 16; // ms — ~60fps cap, like Bubble Tea

// === Cell-level diffing state ===
// Replaces line-level tuiPrevLines approach. Each cell stores the character
// and its pre-computed SGR attribute string. Diffing per-cell instead of per-line
// means only changed characters emit escape sequences — the approach used by
// tcell (gocui/lazygit) and Ratatui's Buffer.
let tuiCellWidth = 0;
let tuiCellHeight = 0;
let tuiCurrCells = null; // current frame: flat array of {ch, sgr}
let tuiPrevCells = null; // previous frame: for diffing
let tuiLastScreenData = null; // raw screen data for resize bridge

/** Allocate or resize cell buffers. Sentinel-fills prev to force full redraw. */
function tuiEnsureCellBuffers(w, h) {
  if (w <= 0 || h <= 0) return;
  if (w === tuiCellWidth && h === tuiCellHeight && tuiCurrCells) return;
  tuiCellWidth = w;
  tuiCellHeight = h;
  const size = w * h;
  tuiCurrCells = new Array(size);
  tuiPrevCells = new Array(size);
  for (let i = 0; i < size; i++) {
    tuiCurrCells[i] = { ch: ' ', sgr: '', link: '' };
    tuiPrevCells[i] = { ch: '\x00', sgr: '\x00', link: '\x00' }; // sentinel → forces full redraw
  }
}

/** Mark all prev cells as dirty so next flush redraws everything. */
function tuiInvalidatePrevCells() {
  if (!tuiPrevCells) return;
  for (let i = 0; i < tuiPrevCells.length; i++) {
    tuiPrevCells[i].ch = '\x00';
    tuiPrevCells[i].sgr = '\x00';
    tuiPrevCells[i].link = '\x00';
  }
}

/** Fill current cell buffer from Elm screen data (array of lines of styled spans). */
function tuiFillCells(screenData) {
  const w = tuiCellWidth;
  const h = tuiCellHeight;
  // Clear all cells to spaces with no style
  for (let i = 0; i < w * h; i++) {
    tuiCurrCells[i].ch = ' ';
    tuiCurrCells[i].sgr = '';
    tuiCurrCells[i].link = '';
  }
  if (!screenData) return;
  // Fill from screen data spans
  const lineCount = Math.min(screenData.length, h);
  for (let row = 0; row < lineCount; row++) {
    let col = 0;
    for (const span of screenData[row]) {
      const sgr = tuiStyleCodes(span.style);
      const link = span.style.hyperlink || '';
      // Iterate codepoints (handles multi-byte chars like box-drawing ╭─╮)
      for (const ch of span.text) {
        if (col >= w) break;
        const idx = row * w + col;
        tuiCurrCells[idx].ch = ch;
        tuiCurrCells[idx].sgr = sgr;
        tuiCurrCells[idx].link = link;
        col++;
      }
    }
  }
}

/**
 * Diff current cells against previous cells, write only changes to terminal.
 * Three key optimizations from tcell/ratatui:
 * 1. Skip unchanged cells entirely (the big win)
 * 2. Cache cursor position — skip movement for adjacent dirty cells
 * 3. Cache active SGR — skip style sequences for same-styled cells
 */
function tuiFlushCells(stdout) {
  tuiLastRenderTime = Date.now();
  const w = tuiCellWidth;
  const h = tuiCellHeight;
  if (!tuiCurrCells || !tuiPrevCells || w === 0 || h === 0) return;

  let buf = '\x1b[?2026h'; // begin synchronized update
  let dirty = false;
  let cRow = -1; // tracked cursor row (0-indexed)
  let cCol = -1; // tracked cursor col (0-indexed)
  let cSgr = null; // currently active SGR string on the terminal
  let cLink = null; // currently active OSC 8 hyperlink URL (null = none)

  for (let row = 0; row < h; row++) {
    for (let col = 0; col < w; col++) {
      const idx = row * w + col;
      const curr = tuiCurrCells[idx];
      const prev = tuiPrevCells[idx];

      // Skip unchanged cells
      if (curr.ch === prev.ch && curr.sgr === prev.sgr && curr.link === prev.link) continue;

      dirty = true;
      // Cursor movement: only emit when cursor isn't already here
      if (cRow !== row || cCol !== col) {
        if (cRow === row) {
          // Same row — use CUF (relative) or CHA (absolute column)
          const gap = col - cCol;
          if (gap === 1) {
            buf += '\x1b[C';
          } else if (gap > 1 && gap <= 4) {
            buf += `\x1b[${gap}C`;
          } else {
            buf += `\x1b[${col + 1}G`;
          }
        } else {
          // Different row — CUP (absolute positioning)
          buf += `\x1b[${row + 1};${col + 1}H`;
        }
      }

      // Style: only emit when SGR differs from current terminal state.
      // Use separate reset + apply (not combined \x1b[0;...m) to avoid
      // parser issues with 256-color/truecolor sub-parameter sequences.
      if (curr.sgr !== cSgr) {
        buf += '\x1b[0m';
        if (curr.sgr !== '') {
          buf += `\x1b[${curr.sgr}m`;
        }
        cSgr = curr.sgr;
      }

      // Hyperlink: emit OSC 8 sequences when link state changes.
      // Format: \x1b]8;;URL\x1b\\ to open, \x1b]8;;\x1b\\ to close.
      // Unsupported terminals silently ignore OSC 8.
      if (curr.link !== cLink) {
        if (cLink) {
          buf += '\x1b]8;;\x1b\\'; // close previous link
        }
        if (curr.link) {
          buf += `\x1b]8;;${curr.link}\x1b\\`; // open new link
        }
        cLink = curr.link;
      }

      buf += curr.ch;
      cCol = col + 1; // cursor auto-advances after write
      cRow = row;

      // Sync prev buffer so next frame diffs correctly
      prev.ch = curr.ch;
      prev.sgr = curr.sgr;
      prev.link = curr.link;
    }

    // Note: no \x1b[K here — unlike the old line-level approach, cell-level
    // diffing explicitly tracks every cell including trailing spaces, so EL
    // is not needed and would destructively erase unchanged cells to the right.
  }

  // Close any open hyperlink at end of frame
  if (cLink) {
    buf += '\x1b]8;;\x1b\\';
  }

  // Reset style at end of frame to leave terminal clean
  if (cSgr !== null && cSgr !== '') {
    buf += '\x1b[0m';
  }

  buf += '\x1b[?2026l'; // end synchronized update

  if (dirty) {
    stdout.write(buf);
  }
}

/**
 * Detect terminal color profile from environment variables.
 * Follows charmbracelet/colorprofile's precedence order — the most
 * battle-tested approach across the Go TUI ecosystem.
 *
 * Returns: 'truecolor' | '256' | '16' | 'mono'
 */
function tuiDetectColorProfile() {
  const env = process.env;

  // NO_COLOR (https://no-color.org/): any non-empty value disables color.
  // Keeps bold/italic/underline — only strips color codes.
  if (env.NO_COLOR != null && env.NO_COLOR !== '') {
    return 'mono';
  }

  // COLORTERM: the most reliable truecolor indicator
  const colorterm = (env.COLORTERM || '').toLowerCase();
  if (colorterm === 'truecolor' || colorterm === '24bit') {
    return 'truecolor';
  }

  const term = (env.TERM || '').toLowerCase();

  // Known truecolor terminals (from charmbracelet/colorprofile)
  const truecolorTermPrefixes = [
    'alacritty', 'kitty', 'ghostty', 'wezterm',
    'foot', 'contour', 'rio', 'st-',
  ];
  if (truecolorTermPrefixes.some(t => term.startsWith(t)) || term === 'st') {
    return 'truecolor';
  }

  // Windows Terminal
  if (env.WT_SESSION) {
    return 'truecolor';
  }

  // TERM_PROGRAM: iTerm2, Hyper, mintty
  const termProgram = (env.TERM_PROGRAM || '').toLowerCase();
  if (['iterm.app', 'hyper', 'mintty'].includes(termProgram)) {
    return 'truecolor';
  }

  // TERM suffix checks
  if (term.endsWith('-direct')) return 'truecolor';
  if (term.includes('256color')) return '256';

  // CLICOLOR=0 means no color
  if (env.CLICOLOR === '0') return 'mono';

  // Safe default for any recognized terminal
  return '16';
}


/**
 * Convert RGB to nearest 256-color palette index.
 * Colors 16-231: 6x6x6 RGB cube. Colors 232-255: 24-step grayscale.
 * Same algorithm used by charmbracelet/colorprofile and Rich.
 */
function tuiRgbTo256(r, g, b) {
  // Check if it's close to grayscale
  if (Math.abs(r - g) <= 2 && Math.abs(g - b) <= 2) {
    if (r < 8) return 16;
    if (r > 248) return 231;
    return Math.round((r - 8) / 247 * 24) + 232;
  }
  // Map to 6x6x6 cube
  return 16
    + 36 * Math.round(r / 255 * 5)
    + 6 * Math.round(g / 255 * 5)
    + Math.round(b / 255 * 5);
}

/**
 * Convert a 256-color index to the nearest ANSI 16-color code.
 * Standard colors (0-7) map directly. Bright colors (8-15) map to bright.
 * Extended colors (16-255) use a simplified nearest-match.
 */
function tuiColor256To16(index, isBackground) {
  const offset = isBackground ? 10 : 0;
  // Standard 16 colors map directly
  if (index < 8) return 30 + index + offset;
  if (index < 16) return 82 + index + offset; // 90 + (index - 8) + offset

  // Extended colors: convert to RGB, then find nearest ANSI color
  let r, g, b;
  if (index >= 232) {
    // Grayscale ramp
    const v = (index - 232) * 10 + 8;
    r = v; g = v; b = v;
  } else {
    // 6x6x6 cube
    const ci = index - 16;
    r = Math.floor(ci / 36) * 51;
    g = Math.floor((ci % 36) / 6) * 51;
    b = (ci % 6) * 51;
  }
  return tuiRgbTo16(r, g, b, isBackground);
}

/**
 * Convert RGB to nearest ANSI 16-color SGR code.
 * Uses weighted distance in RGB space (redmean approximation, same as Rich).
 */
function tuiRgbTo16(r, g, b, isBackground) {
  const offset = isBackground ? 10 : 0;
  // The 16 ANSI colors in RGB (approximate, terminal-dependent)
  const ansi16 = [
    [0,0,0], [170,0,0], [0,170,0], [170,85,0],
    [0,0,170], [170,0,170], [0,170,170], [170,170,170],
    [85,85,85], [255,85,85], [85,255,85], [255,255,85],
    [85,85,255], [255,85,255], [85,255,255], [255,255,255],
  ];
  let bestIdx = 0;
  let bestDist = Infinity;
  for (let i = 0; i < 16; i++) {
    const [cr, cg, cb] = ansi16[i];
    // Redmean weighted distance (better perceptual match than Euclidean)
    const rmean = (r + cr) / 2;
    const dr = r - cr, dg = g - cg, db = b - cb;
    const dist = (2 + rmean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rmean) / 256) * db * db;
    if (dist < bestDist) {
      bestDist = dist;
      bestIdx = i;
    }
  }
  return String(bestIdx < 8 ? 30 + bestIdx + offset : 82 + bestIdx + offset);
}


function tuiCleanup() {
  if (!tuiActive) return;
  tuiActive = false;
  if (tuiDebugLog) {
    try {
      fs.writeSync(tuiDebugLog, `[${Date.now()}] tuiCleanup called\n`);
      fs.writeSync(tuiDebugLog, `  queue: ${tuiEventQueue.length}\n`);
      fs.closeSync(tuiDebugLog);
    } catch (e) {}
    tuiDebugLog = null;
  }
  const stdout = process.stdout;

  // Step 1: Disable mouse tracking and bracketed paste FIRST, while still
  // in raw mode. This tells the terminal to stop generating mouse events.
  // Must happen before setRawMode(false) — otherwise buffered mouse events
  // get echoed as visible escape sequences in the shell after exit.
  stdout.write(
    "\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l" + // disable all mouse modes
    "\x1b[?2004l"                                        // disable bracketed paste
  );

  // Step 2: Replace data listener with a no-op drain to consume and discard
  // any mouse/key events still in the stdin buffer or kernel pipe.
  process.stdin.removeAllListeners("data");
  process.stdin.on("data", () => {}); // consume and discard
  process.stdout.removeAllListeners("resize");

  // Step 3: Clear internal state
  tuiEventResolve = null;
  tuiEventQueue = [];
  tuiStdinLeftover = "";
  tuiCurrCells = null;
  tuiPrevCells = null;
  tuiLastScreenData = null;
  tuiCellWidth = 0;
  tuiCellHeight = 0;
  if (tuiTickTimer) {
    clearInterval(tuiTickTimer);
    tuiTickTimer = null;
    tuiTickInterval = null;
  }

  // Step 4: Now safe to exit raw mode — mouse tracking is already off,
  // and the drain listener will consume any stragglers.
  process.stdin.removeAllListeners("data");
  if (process.stdin.isTTY && process.stdin.isRaw) {
    process.stdin.setRawMode(false);
  }
  process.stdin.pause();

  // Step 5: Complete terminal restoration
  stdout.write(
    "\x1b[0m" +                  // reset all text attributes
    "\x1b[?25h" +                // show cursor
    "\x1b[?1l\x1b>" +            // reset cursor keys to normal mode (DECRST + DECKPNM)
    "\x1b[?1049l"                // exit alternate screen (restores saved screen)
  );
}

// Ensure terminal is restored on unexpected exit
process.on("exit", tuiCleanup);
process.on("SIGINT", () => {
  tuiCleanup();
  process.exit(130);
});
process.on("SIGTERM", () => {
  tuiCleanup();
  process.exit(143);
});

async function runTuiInit(req) {
  tuiActive = true;
  tuiLastScreenData = null; // reset for cell-level diffing
  const stdout = process.stdout;

  // Single atomic write to avoid timing gaps where scroll events could leak.
  // Sequence: alternate screen, hide cursor, mouse tracking (button events +
  // SGR encoding), clear screen. tcell and Bubble Tea use the same modes.
  stdout.write(
    "\x1b[?1049h" + // enter alternate screen
    "\x1b[?25l" +   // hide cursor
    "\x1b[?1000h" + // enable button event mouse tracking (captures scroll)
    "\x1b[?1006h" + // enable SGR mouse encoding (decimal, no coord limit)
    "\x1b[?2004h" + // enable bracketed paste mode
    "\x1b[2J\x1b[H" // clear screen, cursor to top-left
  );

  // Set raw mode
  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.setEncoding("utf8");
  }

  // Persistent stdin listener — stays active during Elm processing so events
  // arriving between waits get queued instead of lost. This is gocui's pattern:
  // events queue up, and the next wait drains them all at once.
  tuiEventQueue = [];
  tuiEventResolve = null;
  tuiStdinLeftover = "";

  // Debug logging: set ELM_TUI_DEBUG=1 to write tui-debug.log for diagnosing input issues
  if (process.env.ELM_TUI_DEBUG) {
    try {
      tuiDebugLog = fs.openSync("tui-debug.log", "w");
      fs.writeSync(tuiDebugLog, `[${new Date().toISOString()}] TUI init\n`);
    } catch (e) { tuiDebugLog = null; }
  }

  process.stdin.on("data", (data) => {
    if (tuiDebugLog) {
      const raw = data.toString();
      const escaped = raw.replace(/\x1b/g, "\\x1b").replace(/[\x00-\x1f]/g, (c) => "\\x" + c.charCodeAt(0).toString(16).padStart(2, "0"));
      fs.writeSync(tuiDebugLog, `[${Date.now()}] stdin(${raw.length}): ${escaped}\n`);
      if (tuiStdinLeftover) {
        const loEsc = tuiStdinLeftover.replace(/\x1b/g, "\\x1b").replace(/[\x00-\x1f]/g, (c) => "\\x" + c.charCodeAt(0).toString(16).padStart(2, "0"));
        fs.writeSync(tuiDebugLog, `  leftover(${tuiStdinLeftover.length}): ${loEsc}\n`);
      }
    }

    const event = tuiParseTerminalInput(data);

    if (tuiDebugLog) {
      if (event) {
        fs.writeSync(tuiDebugLog, `  -> event: ${JSON.stringify(event)}\n`);
      } else {
        fs.writeSync(tuiDebugLog, `  -> null (no event)\n`);
      }
      if (tuiStdinLeftover) {
        const loEsc = tuiStdinLeftover.replace(/\x1b/g, "\\x1b").replace(/[\x00-\x1f]/g, (c) => "\\x" + c.charCodeAt(0).toString(16).padStart(2, "0"));
        fs.writeSync(tuiDebugLog, `  leftover after: ${loEsc}\n`);
      }
      fs.writeSync(tuiDebugLog, `  queue: ${tuiEventQueue.length}, resolve: ${!!tuiEventResolve}\n`);
    }

    if (!event) return;

    if (event._exit) {
      tuiCleanup();
      process.exit(130);
      return;
    }

    // Track scroll for coalescing
    if (event.type === "mouse" && (event.action === "scrollUp" || event.action === "scrollDown")) {
      tuiLastScrollDir = event.action;
      tuiLastScrollTime = Date.now();
    }

    if (tuiEventResolve) {
      // A wait is pending — resolve immediately (zero latency)
      const resolve = tuiEventResolve;
      tuiEventResolve = null;
      resolve(event);
    } else {
      // No wait pending (Elm is processing) — queue for next wait.
      // Net scroll coalescing: merge ALL scroll events (both directions)
      // into a single net-delta event. This cancels out macOS rubber-band
      // bounce events mathematically: 5 scrollDowns + 3 scrollUps (bounce)
      // = net scrollDown with amount 2. One smooth scroll, no oscillation.
      const last = tuiEventQueue.length > 0 ? tuiEventQueue[tuiEventQueue.length - 1] : null;
      const isScroll = event.type === "mouse" && (event.action === "scrollUp" || event.action === "scrollDown");
      const lastIsScroll = last && last.type === "mouse" && (last.action === "scrollUp" || last.action === "scrollDown");
      if (isScroll && lastIsScroll) {
        // Net the deltas: down is positive, up is negative
        const lastDelta = last.action === "scrollDown" ? (last.amount || 1) : -(last.amount || 1);
        const newDelta = event.action === "scrollDown" ? (event.amount || 1) : -(event.amount || 1);
        const net = lastDelta + newDelta;
        if (net > 0) {
          last.action = "scrollDown";
          last.amount = net;
        } else if (net < 0) {
          last.action = "scrollUp";
          last.amount = -net;
        } else {
          // Net zero — remove the scroll event entirely
          tuiEventQueue.pop();
        }
      } else {
        tuiEventQueue.push(event);
      }
    }
  });

  // Listen for terminal resize.
  // 1. Immediately re-render last frame (instant visual feedback, no Elm round-trip)
  // 2. Queue a resize event for Elm to update Layout with new dimensions
  process.stdout.on("resize", () => {
    // Instant redraw: re-fill cell buffer from last screen data at new dimensions
    const newW = process.stdout.columns || 80;
    const newH = process.stdout.rows || 24;
    tuiEnsureCellBuffers(newW, newH);
    if (tuiLastScreenData && tuiLastScreenData.length > 0) {
      tuiFillCells(tuiLastScreenData);
      tuiInvalidatePrevCells();
      tuiFlushCells(process.stdout);
    }

    // Queue resize event for Elm (coalesce: replace any existing resize)
    const resizeEvent = {
      type: "resize",
      width: newW,
      height: newH,
    };

    if (tuiEventResolve) {
      const resolve = tuiEventResolve;
      tuiEventResolve = null;
      resolve(resizeEvent);
    } else {
      const existingIdx = tuiEventQueue.findIndex(e => e.type === "resize");
      if (existingIdx >= 0) {
        tuiEventQueue[existingIdx] = resizeEvent;
      } else {
        tuiEventQueue.push(resizeEvent);
      }
    }
  });

  // Initialize cell buffers for cell-level diffing
  tuiEnsureCellBuffers(stdout.columns || 80, stdout.rows || 24);

  // Detect color profile once at init (charmbracelet/colorprofile approach)
  tuiColorProfile = tuiDetectColorProfile();

  return jsonResponse(req, {
    width: stdout.columns || 80,
    height: stdout.rows || 24,
    colorProfile: tuiColorProfile,
  });
}

async function runTuiRender(req) {
  tuiRenderScreen(req.body.args[0]);
  return jsonResponse(req, null);
}

/**
 * Render screen data with cell-level diffing. Fills cell buffer from screen data,
 * then diffs each cell against the previous frame. Only changed cells emit escape
 * sequences — the tcell/ratatui approach ("cell-level delta rendering").
 */
function tuiRenderScreen(screenData) {
  const stdout = process.stdout;
  const w = stdout.columns || 80;
  const h = stdout.rows || 24;

  // Save for resize bridge
  tuiLastScreenData = screenData;

  // Ensure cell buffers match terminal dimensions
  tuiEnsureCellBuffers(w, h);

  // Fill current cell buffer from screen data
  tuiFillCells(screenData);

  // Frame rate throttle (like Bubble Tea's 60fps renderer cap).
  // Skip intermediate renders so slow displays aren't overwhelmed.
  // Schedule a deferred render so the final frame is always shown.
  const now = Date.now();
  if (now - tuiLastRenderTime < TUI_MIN_RENDER_INTERVAL) {
    // Too soon — schedule deferred render for when the interval elapses
    if (tuiPendingRender) clearTimeout(tuiPendingRender);
    tuiPendingRender = setTimeout(() => {
      tuiPendingRender = null;
      tuiFlushCells(stdout);
    }, TUI_MIN_RENDER_INTERVAL - (now - tuiLastRenderTime));
    return;
  }
  if (tuiPendingRender) {
    clearTimeout(tuiPendingRender);
    tuiPendingRender = null;
  }

  tuiFlushCells(stdout);
}

/** Generate a cache key for a style object for quick comparison */
function tuiStyleKey(style) {
  if (!style) return "";
  let key = "";
  if (style.bold) key += "B";
  if (style.dim) key += "D";
  if (style.italic) key += "I";
  if (style.underline) key += "U";
  if (style.strikethrough) key += "S";
  if (style.inverse) key += "V";
  if (style.foreground) key += "f" + JSON.stringify(style.foreground);
  if (style.background) key += "b" + JSON.stringify(style.background);
  return key;
}

/** Generate SGR codes string for a style (without the ESC[ prefix or m suffix) */
function tuiStyleCodes(style) {
  const codes = [];
  if (style.bold) codes.push("1");
  if (style.dim) codes.push("2");
  if (style.italic) codes.push("3");
  if (style.underline) codes.push("4");
  if (style.strikethrough) codes.push("9");
  if (style.inverse) codes.push("7");
  if (style.foreground) codes.push(tuiColorToAnsi(style.foreground, false));
  if (style.background) codes.push(tuiColorToAnsi(style.background, true));
  return codes.join(";");
}

async function runTuiWaitEvent(req) {
  return runTuiWaitEventImpl(req);
}

async function runTuiWaitEventImpl(req) {
  const stdout = process.stdout;

  const makeResponse = (events) => {
    if (events.length === 1) {
      return jsonResponse(req, {
        event: events[0],
        width: stdout.columns || 80,
        height: stdout.rows || 24,
      });
    }
    return jsonResponse(req, {
      events: events,
      width: stdout.columns || 80,
      height: stdout.rows || 24,
    });
  };

  // If events queued up during Elm processing, return them all immediately.
  // This is the gocui drain pattern — zero latency, natural batching.
  if (tuiEventQueue.length > 0) {
    const events = tuiEventQueue;
    tuiEventQueue = [];
    return makeResponse(events);
  }

  // No queued events — wait for the next one
  return new Promise((resolve) => {
    tuiEventResolve = (event) => {
      resolve(makeResponse([event]));
    };
  });
}

async function runTuiRenderAndWait(req) {
  // Combined render + wait in a single BackendTask round-trip
  const args = req.body.args[0];
  tuiRenderScreen(args.screen);

  // Start/stop tick timer based on subscription interests.
  // Uses the interval from Elm's Sub.every (defaults to 50ms for backwards compat).
  const interests = args.interests || [];
  const wantsTick = interests.includes("tick");
  const tickInterval = args.tickInterval || 50;
  if (wantsTick && (!tuiTickTimer || tuiTickInterval !== tickInterval)) {
    if (tuiTickTimer) {
      clearInterval(tuiTickTimer);
    }
    tuiTickInterval = tickInterval;
    tuiTickTimer = setInterval(() => {
      const tickEvent = { type: "tick" };
      if (tuiEventResolve) {
        const resolve = tuiEventResolve;
        tuiEventResolve = null;
        resolve(tickEvent);
      } else {
        // Coalesce: only keep one tick in the queue
        const hasQueuedTick = tuiEventQueue.some(e => e.type === "tick");
        if (!hasQueuedTick) {
          tuiEventQueue.push(tickEvent);
        }
      }
    }, tickInterval);
  } else if (!wantsTick && tuiTickTimer) {
    clearInterval(tuiTickTimer);
    tuiTickTimer = null;
    tuiTickInterval = null;
  }

  return runTuiWaitEventImpl(req);
}


async function runTuiExit(req) {
  tuiEventResolve = null;
  tuiEventQueue = [];
  process.stdin.removeAllListeners("data");
  tuiCleanup();
  return jsonResponse(req, null);
}

/**
 * Parse terminal input, potentially containing multiple escape sequences.
 * Returns the first parseable event, and queues any additional events found
 * in the same data chunk (fixes dropped events from concatenated sequences).
 *
 * Maintains a leftover buffer across calls to handle data chunks that split
 * mid-escape-sequence. Without this, rapid scroll on macOS trackpads can
 * produce partial sequences like "64;119;45M" (missing the \x1b[< prefix)
 * that would be misinterpreted as keypresses.
 */
function tuiParseTerminalInput(data) {
  const s = tuiStdinLeftover + data.toString();
  tuiStdinLeftover = "";

  // Ctrl+C
  if (s === "\x03") {
    return { _exit: true };
  }

  // Try to parse multiple sequences from one data chunk.
  // Terminal emulators can concatenate escape sequences (especially during
  // fast scroll where iTerm2 sends N sequences from one OS event).
  const { events, leftover } = tuiParseAllEvents(s);
  tuiStdinLeftover = leftover;

  if (events.length === 0) {
    return null;
  }
  // Queue additional events beyond the first
  for (let i = 1; i < events.length; i++) {
    if (tuiEventResolve) {
      const resolve = tuiEventResolve;
      tuiEventResolve = null;
      resolve(events[i]);
    } else {
      tuiEventQueue.push(events[i]);
    }
  }
  return events[0];
}

// tuiParseAllEvents and tuiParseSingleEvent are imported from tui-parser.js

/**
 * Convert a color value to an SGR code string, with automatic degradation
 * based on the detected terminal color profile.
 *
 * The Elm app writes colors in the highest fidelity it wants. The renderer
 * transparently downgrades based on tuiColorProfile — matching charmbracelet's
 * approach where the app always writes TrueColor and the framework handles it.
 *
 * Degradation path: TrueColor → 256-color → 16-color → mono (no color)
 */
function tuiColorToAnsi(color, isBackground) {
  const profile = tuiColorProfile || 'truecolor';

  // NO_COLOR / mono: strip all color codes (bold/italic preserved in tuiStyleCodes)
  if (profile === 'mono') return "";

  const offset = isBackground ? 10 : 0;

  if (typeof color === "string") {
    // Named ANSI colors (16-color) — always supported in any non-mono profile
    const colorMap = {
      black: 30, red: 31, green: 32, yellow: 33, blue: 34, magenta: 35, cyan: 36, white: 37,
      brightBlack: 90, brightRed: 91, brightGreen: 92, brightYellow: 93,
      brightBlue: 94, brightMagenta: 95, brightCyan: 96, brightWhite: 97,
    };
    const code = colorMap[color];
    if (code !== undefined) {
      return String(code >= 90 ? code + (isBackground ? 10 : 0) : code + offset);
    }
    return "";
  }

  if (color.r !== undefined) {
    // Truecolor (24-bit) — degrade based on profile
    if (profile === 'truecolor') {
      return `${isBackground ? 48 : 38};2;${color.r};${color.g};${color.b}`;
    }
    if (profile === '256') {
      return `${isBackground ? 48 : 38};5;${tuiRgbTo256(color.r, color.g, color.b)}`;
    }
    // 16-color: map to nearest ANSI color
    return tuiRgbTo16(color.r, color.g, color.b, isBackground);
  }

  if (color.color256 !== undefined) {
    // 256-color — degrade to 16-color if needed
    if (profile === 'truecolor' || profile === '256') {
      return `${isBackground ? 48 : 38};5;${color.color256}`;
    }
    // 16-color: map 256 to nearest ANSI color
    return tuiColor256To16(color.color256, isBackground);
  }

  return "";
}
