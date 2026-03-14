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
 */
export async function runGenerator(
  cliOptions,
  portsFile,
  elmModule,
  scriptModuleName,
  versionMessage
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
 * @param {unknown} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @returns {Promise<({is404: boolean;} & ({kind: 'json';contentJson: string;} | {kind: 'html';htmlString: string;} | {kind: 'api-response';body: string;}))>}
 * @param {string[]} cliOptions
 * @param {PortsFile} portsFile
 * @param {typeof import("fs") | import("memfs").IFs} fs
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
  versionMessage
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

    app = elmModule.Elm.ScriptMain.init({
      flags: {
        compatibilityKey,
        argv: ["", `elm-pages run ${scriptModuleName}`, ...cliOptions],
        versionMessage: versionMessage || "",
        colorMode: detectColorSupport(),
      },
    });

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
          outgoingBytes.map(({ key, data }) => [
            key,
            dataViewToBuffer(data),
          ])
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
          ? { ...args.body, body: Buffer.from(dataViewToBuffer(contentDatPayload)).toString("base64") }
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
          outgoingBytes.map(({ key, data }) => [
            key,
            dataViewToBuffer(data),
          ])
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
      typeof error === "string"
        ? error
        : error.message || String(error);

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
        return [requestHash, await runFileExists(requestToPerform, patternsToWatch)];
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
  } else if (typeof payloadOrHeaders === "string" && payloadOrHeaders.length > 0) {
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
      const elmJson = JSON.parse(await fsPromises.readFile(elmJsonPath, "utf8"));
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
    wire3Data = typeof base64Data === "string" ? Buffer.from(base64Data, "base64") : null;
  }

  if (
    typeof schemaHash !== "string" ||
    schemaHash.length === 0 ||
    !wire3Data
  ) {
    throw {
      title: "Invalid db-write payload",
      message:
        "Expected hash and data fields when writing to the database.",
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
    const { saveSchemaSource, computeSchemaHashFromSource } = await import("./db-schema.js");
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
  const minRetryDelayMs = readPositiveIntEnv(
    "ELM_PAGES_DB_LOCK_RETRY_MS",
    50
  );
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
        const jitterMs = Math.floor(Math.random() * Math.max(1, minRetryDelayMs));
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
    wire3Data = typeof base64Data === "string" ? Buffer.from(base64Data, "base64") : null;
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
  const {
    readSchemaVersion,
    saveSchemaSource,
    computeSchemaHashFromSource,
  } = await import("./db-schema.js");

  const schemaVersion = await readSchemaVersion(cwd);

  // Compute hash from current Db.elm
  let schemaHash;
  try {
    const currentDb = await findCurrentDbElm(cwd);
    if (!currentDb) {
      throw { title: "Migration write failed", message: "Could not find Db.elm to compute schema hash." };
    }
    schemaHash = computeSchemaHashFromSource(currentDb.source);
    await saveSchemaSource(cwd, schemaHash, currentDb.source);
  } catch (error) {
    if (error.title) throw error;
    throw { title: "Migration write failed", message: `Error computing schema hash: ${error.message}` };
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
    try { await fsPromises.unlink(tmpPath); } catch (_) {}
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
  for (let index = 0; index < secrets.length; index++) {
    const signed = cookie.unsign(input, secrets[index]);
    if (signed) {
      return signed;
    }
  }
  return null;
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
