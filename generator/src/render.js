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
 * @typedef {Errors | ApiResponse | PageProgress | DoHttp | SendApiResponse | Port | string} FromElm
 *
 * @typedef {{ tag: "Errors"; args: [ErrorFromElm]; }} Errors
 * @typedef {any} ErrorFromElm
 *
 * @typedef {{ tag: "ApiResponse"; args: []; }} ApiResponse
 *
 * @typedef {{ tag: "PageProgress"; args: [ToJsSuccessPayloadNew]; }} PageProgress
 * @typedef {{ route: string; html: string; contentJson: { [key : string]: string }; errors: string[]; head: HeadTag[]; title: string; staticHttpCache: { [key : string]: string }; is404: boolean; statusCode: number; headers : { [key: string]: string[] }; }} ToJsSuccessPayloadNew
 *
 * @typedef {SimpleTag | StructuredDataTag | RootModifierTag | StrippedTag} HeadTag
 * @typedef {{ type: "head"; name: string; attributes: [string, string][]; }} SimpleTag
 * @typedef {{ type: "json-ld"; contents: any; }} StructuredDataTag
 * @typedef {{ type: "root"; keyValuePair: [string, string]; }} RootModifierTag
 * @typedef {{ type: "stripped"; message: string; }} StrippedTag
 *
 * @typedef {{ tag: "DoHttp"; args: [[string, ElmRequest][]]; }} DoHttp
 * @typedef {InternalRequest | import("./request-cache.js").GenericRequest} ElmRequest
 *
 * @typedef {LogRequest | WriteFileRequest | SleepRequest | WhichRequest | QuestionRequest | EncryptRequest | DecryptRequest | TimeRequest | FileReadRequest | EnvRequest | GlobRequest | RandomSeedRequest | StartSpinnerRequest | StopSpinnerRequest | StreamRequest} InternalRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://log", { message: string }>} LogRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://write-file", { path: string; body: string }>} WriteFileRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://sleep", { milliseconds: number }>} SleepRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://which", string>} WhichRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://question", { prompt: string }>} QuestionRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://encrypt", { values: any; secret: string }>} EncryptRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://decrypt", { input: string; secrets: string[] }>} DecryptRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://now", null>} TimeRequest
 * @typedef {InternalRequestString<"elm-pages-internal://read-file">} FileReadRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://env", string>} EnvRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://glob", { pattern: string; options: GlobOptions; }>} GlobRequest
 * @typedef {{ dot: boolean; followSymbolicLinks: boolean; caseSensitiveMatch: boolean; gitIgnore: boolean; deep?: number; onlyFiles: boolean; onlyDirectories: boolean; stats: boolean; }} GlobOptions
 * @typedef {InternalRequestJson<"elm-pages-internal://randomSeed", null>} RandomSeedRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://start-spinner", { text: string; immediateStart: boolean; spinner?: string; spinnerId?: string; }>} StartSpinnerRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://stop-spinner", { spinnerId: string; completionFn: string; completionText: string?; }>} StopSpinnerRequest
 * @typedef {InternalRequestJson<"elm-pages-internal://stream", { kind: string; parts: StreamPart[]}>} StreamRequest
 *
 * @typedef {SimplePart<"unzip"> | SimplePart<"gzip"> | SimplePart<"stdin"> | SimplePart<"stdout"> | SimplePart<"stderr"> | FromStringPart | CommandPart | HttpWritePart | FileReadPart | FileWritePart | CustomReadPart | CustomWritePart | CustomDuplexPart} StreamPart
 * @typedef {PartWith<"fromString", { string: string; }>} FromStringPart
 * @typedef {PartWith<"command", { command: string; args: string[]; allowNon0Status: boolean; output: "Ignore" | "Print" | "MergeWithStdout" | "InsteadOfStdout"; timeoutInMs: number?; }>} CommandPart
 * @typedef {PartWith<"httpWrite", { url: string; method: string; headers: { key: string; value: string; }[]; body?: import("./request-cache.js").StaticHttpBody; retries: number?; timeoutInMs: number?; }>} HttpWritePart
 * @typedef {PartWith<"fileRead", { path: string; }>} FileReadPart
 * @typedef {PartWith<"fileWrite", { path: string; }>} FileWritePart
 * @typedef {PartWith<"customRead", { portName: string; input: any; }>} CustomReadPart
 * @typedef {PartWith<"customWrite", { portName: string; input: any; }>} CustomWritePart
 * @typedef {PartWith<"customDuplex", { portName: string; input: any; }>} CustomDuplexPart
 *
 * @typedef {{ tag: "ApiResponse"; args: [any]; }} SendApiResponse
 *
 * @typedef {{ tag: "Port"; args: [string]; }} Port
 *
 * @typedef {{ Elm: { ScriptMain: { init: (flags: { flags: ScriptFlags; }) => ElmApp; }; Main: { init: (flags : {flags : MainFlags; }) => ElmApp; }; }; }} ElmModule
 * @typedef {{ fromJsPort: FromJsPort<{ tag: string; data: any; }>; toJsPort: ToJsPort<FromElm>; sendPageData: ToJsPort<FromElm>; gotBatchSub: FromJsPort<{ [k: string]: any; }> }} Ports
 * @typedef {{ ports: Ports; die: () => void; }} ElmApp
 * @typedef {{ compatibilityKey: number; argv: string[]; versionMessage: "1.2.3" }} ScriptFlags
 * @typedef {{ compatibilityKey: number; mode: string; request: { payload: any; kind: "single-page"; jsonOnly: boolean; }; }} MainFlags
 */

/**
 * @template Key
 * @typedef {{ name: Key; }} SimplePart<Key>
 */

/**
 * @template Key
 * @template Values
 * @typedef {{ name: Key; } & Values} PartWith<Key,Values>
 */

/**
 * @template Key
 * @template Body
 * @typedef {{ url: Key; method: string; headers: [string, string][]; body: { tag: "json"; args: [Body] }; cacheOptions?: any; env: { [key : string]: string }; dir: string[]; quiet: boolean; }} InternalRequestJson<Key,Body>
 */

/**
 * @template Key
 * @typedef {{ url: Key; method: string; headers: [string, string][]; body: { tag: "string"; args: [string, string] }; cacheOptions?: any; env: { [key : string]: string }; dir: string[]; quiet: boolean; }} InternalRequestString<Key>
 */

/**
 * @template T
 * @typedef {{ send: (arg0: T) => void; }} FromJsPort<T>
 */
/**
 * @template T
 * @typedef {{ unsubscribe: (callback: (arg: T) => Promise<void>) => void; subscribe: (callback: (arg: T) => Promise<void>) => void; }} ToJsPort<T>
 */

/**
 * @param {string} basePath
 * @param {ElmModule} elmModule
 * @param {string} path
 * @param {{method: string;hostname: string;query: Record<string, string | undefined>;headers: Record<string, string>;host: string;pathname: string;port: number | null;protocol: string;rawUrl: string;}} request
 * @param {(patterns: Set<string>) => void} addBackendTaskWatcher
 * @param {boolean} hasFsAccess
 * @returns
 * @param {any} portsFile
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
    addBackendTaskWatcher
  );
  return result;
}

/**
 * @param {ElmModule} elmModule
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
 * @param {ElmModule} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @returns {Promise<({is404: boolean;} & ({kind: 'json';contentJson: string;} | {kind: 'html';htmlString: string;} | {kind: 'api-response';body: string;}))>}
 * @param {string[]} cliOptions
 * @param {any} portsFile
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
  let patternsToWatch = new Set();
  /**
   * @type {(() => void) | null}
   */
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

    /** @type {ElmApp | null} */
    let app = elmModule.Elm.ScriptMain.init({
      flags: {
        compatibilityKey,
        argv: ["", `elm-pages run ${scriptModuleName}`, ...cliOptions],
        versionMessage: versionMessage || "",
      },
    });
    app.ports.toJsPort.subscribe(portHandler);

    killApp = () => {
      if (app) {
        app.ports.toJsPort.unsubscribe(portHandler);
        app.die();
        app = null;
      }
      // delete require.cache[require.resolve(compiledElmPath)];
    };

    /**
     * @param {FromElm | { oldThing: FromElm; binaryPageData: any; }} newThing
     */
    async function portHandler(newThing) {
      if (!app) {
        // The app is already dead
        return;
      }

      let contentDatPayload;
      let fromElm = newThing;

      if (typeof newThing !== "string" && "oldThing" in newThing) {
        fromElm = newThing.oldThing;
        contentDatPayload = newThing.binaryPageData;
      } else {
        fromElm = newThing;
      }

      if (typeof fromElm === "string" || fromElm.command === "log") {
        console.log(fromElm.value);
      } else {
        switch (fromElm.tag) {
          case "ApiResponse":
            // Finished successfully
            process.exit(0);
            break;

          case "PageProgress":
            const args = fromElm.args[0];
            if (isBytes) {
              resolve(outputBytes(args, contentDatPayload));
            } else {
              resolve(outputString(basePath, args, contentDatPayload));
            }
            break;

          case "DoHttp":
            doHttp(app, fromElm, mode, patternsToWatch, portsFile);
            break;

          case "Errors":
            spinnies.stopAll();
            reject(fromElm.args[0].errorsJson);
            break;

          default:
            console.log(fromElm);
            break;
        }
      }
    }
  }).finally(() => {
    try {
      if (killApp) {
        killApp();
        killApp = null;
      }
    } catch (error) {}
  });
}

/**
 * @param {string} basePath
 * @param {ElmModule} elmModule
 * @param {string} pagePath
 * @param {string} mode
 * @param {{ method: string; hostname: string; query: string; headers: Object; host: string; pathname: string; port: string; protocol: string; rawUrl: string; }} request
 * @param {(patterns: Set<string>) => void} addBackendTaskWatcher
 * @returns {Promise<({is404: boolean; } & ({kind: 'json'; contentJson: string; } | {kind: 'html'; htmlString: string; } | {kind: 'api-response'; body: string; }))>}
 * @param {any} portsFile
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
  let patternsToWatch = new Set();
  /**
   * @type {(() => void) | null}
   */
  let killApp;

  return new Promise((resolve, reject) => {
    const isBytes = pagePath.match(/content\.dat\/?$/);
    const route = pagePath
      .replace(/content\.json\/?$/, "")
      .replace(/content\.dat\/?$/, "");

    const modifiedRequest = { ...request, path: route };

    /** @type {ElmApp | null} */
    let app = elmModule.Elm.Main.init({
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
    app.ports.toJsPort.subscribe(portHandler);
    app.ports.sendPageData.subscribe(portHandler);

    killApp = () => {
      if (app) {
        app.ports.toJsPort.unsubscribe(portHandler);
        app.ports.sendPageData.unsubscribe(portHandler);
        app.die();
        app = null;
      }
      // delete require.cache[require.resolve(compiledElmPath)];
    };

    /**
     * @param {FromElm | { oldThing: FromElm; binaryPageData: any; }} newThing
     */
    async function portHandler(newThing) {
      if (!app) {
        // The app is already dead
        return;
      }

      let contentDatPayload;
      let fromElm;

      if (typeof newThing !== "string" && "oldThing" in newThing) {
        fromElm = newThing.oldThing;
        contentDatPayload = newThing.binaryPageData;
      } else {
        fromElm = newThing;
      }

      if (typeof fromElm === "string" || fromElm.command === "log") {
        console.log(fromElm.value);
      } else {
        switch (fromElm.tag) {
          case "ApiResponse": {
            const args = fromElm.args[0];

            resolve({
              kind: "api-response",
              is404: args.is404,
              statusCode: args.statusCode,
              body: args.body,
            });
            break;
          }

          case "PageProgress": {
            const args = fromElm.args[0];
            if (isBytes) {
              resolve(outputBytes(args, contentDatPayload));
            } else {
              resolve(outputString(basePath, args, contentDatPayload));
            }
            break;
          }

          case "DoHttp":
            doHttp(app, fromElm, mode, patternsToWatch, portsFile);
            break;

          case "Errors":
            spinnies.stopAll();
            reject(fromElm.args[0].errorsJson);
            break;

          default:
            console.log(fromElm);
        }
      }
    }
  }).finally(() => {
    addBackendTaskWatcher(patternsToWatch);
    try {
      if (killApp) {
        killApp();
        killApp = null;
      }
    } catch (error) {}
  });
}

/**
 * @param {{ route?: string; html?: string; contentJson: any; errors?: string[]; head?: HeadTag[]; title?: string; staticHttpCache?: { [key: string]: string; }; is404?: boolean; statusCode: any; headers: any; }} args
 * @param {undefined} contentDatPayload
 */
function outputBytes(args, contentDatPayload) {
  return {
    kind: "bytes",
    is404: false,
    contentJson: JSON.stringify({
      staticData: args.contentJson,
      is404: false,
    }),
    statusCode: args.statusCode,
    headers: args.headers,
    contentDatPayload,
  };
}

/**
 * @param {string} basePath
 * @param {ToJsSuccessPayloadNew} args
 * @param {undefined} contentDatPayload
 */
async function outputString(basePath, args, contentDatPayload) {
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
 * @param {ElmApp} app
 * @param {DoHttp} fromElm
 * @param {string} mode
 * @param {Set<any>} patternsToWatch
 * @param {any} portsFile
 */
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

/**
 * @param {ElmRequest} requestToPerform
 * @param {ElmApp} app
 * @param {any} mode
 * @param {any} patternsToWatch
 * @param {any} portsFile
 */
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

/**
 * @param {GenericRequest} requestToPerform
 * @param {string} mode
 * @param {Record<string, unknown>} portsFile
 */
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

/**
 * @param {InternalRequest} requestToPerform
 * @param {Set<string>} patternsToWatch
 * @param {any} portsFile
 */
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
        JSON.stringify(requestToPerform, null, 2)
      )}`;
  }
}

/**
 * @param {FileReadRequest} req
 * @param {{ add: (arg0: string) => void; }} patternsToWatch
 * @param {{ cwd: string; }} _
 */
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

/**
 * @param {SleepRequest} req
 */
function runSleep(req) {
  const { milliseconds } = req.body.args[0];
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve(null);
    }, milliseconds);
  });
}

/**
 * @param {WhichRequest} req
 */
async function runWhich(req) {
  const command = req.body.args[0];
  try {
    return await which(command);
  } catch (error) {
    return null;
  }
}

/**
 * @param {QuestionRequest} req
 */
async function runQuestion(req) {
  return await question(req.body.args[0]);
}

/**
 * @param {StreamRequest} req
 * @param {any} portsFile
 * @param {{ cwd: string; quiet: any; env: any; }} context
 */
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
    } catch (error) {
      if (lastStream) {
        lastStream.destroy();
      }

      resolve({ error: error.toString() });
    }
  });
}

/**
 * @param {?import('node:stream').Stream} lastStream
 * @param {StreamPart} part
 * @param {{cwd: string; quiet: boolean; env: NodeJS.ProcessEnv; }} _
 * @param {{ [x: string]: (arg0: any, arg1: { cwd: string; quiet: boolean; env: NodeJS.ProcessEnv; }) => any; }} portsFile
 * @param {{ (value: any): void; (arg0: { error: any; }): void; }} resolve
 * @param {boolean} isLastProcess
 * @param {string} kind
 * @returns {Promise<{stream: import('node:stream').Stream; metadata?: any; }>}
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
      break;
    }
    case "command": {
      const { command, args, allowNon0Status, output } = part;
      /** @type {'ignore' | 'inherit'} } */
      let letPrint = quiet ? "ignore" : "inherit";
      /** @type {'ignore' | 'inherit' | 'pipe'} */
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

/**
 * @param {Promise<any>|function|null} func
 */
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

/**
 * @param {ShellRequest} req
 */
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

/**
 * @param {any} cwd
 * @param {{ commands: any; }} commandsAndArgs
 */
function commandAndArgsToString(cwd, commandsAndArgs) {
  return (
    `$ ` +
    commandsAndArgs.commands
      .map((/** @type {{ command: any; args: any; }} */ commandAndArgs) => {
        return [commandAndArgs.command, ...commandAndArgs.args].join(" ");
      })
      .join(" | ")
  );
}

/**
 * @param {{ cwd: any; quiet: any; env: NodeJS.ProcessEnv; captureOutput: any; }} _
 * @param {{ commands: { command: any; args: any; }[]; }} commandAndArgs
 */
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
     * @type {null | import('node:child_process').ChildProcessByStdio<any, Readable, any>}
     */
    let previousProcess = null;
    /**
     * @type {null | import('node:child_process').ChildProcessByStdio<any, Readable, any>}
     */
    let currentProcess = null;

    for (let index = 0; index < commandsAndArgs.commands.length; index++) {
      const { command, args, timeout } = commandsAndArgs.commands[index];
      let timeout_ = timeout ? timeout : undefined;
      /**
       * @type {import('node:child_process').ChildProcess}
       */
      if (previousProcess === null) {
        currentProcess = spawnCallback(command, args, {
          stdio: ["inherit", "pipe", "inherit"],
          timeout: timeout_,
          cwd: cwd,
          env: env,
        });
      } else {
        currentProcess = spawnCallback(command, args, {
          stdio: ["pipe", "pipe", "pipe"],
          timeout: timeout_,
          cwd: cwd,
          env: env,
        });

        previousProcess.stdout.pipe(currentProcess.stdin);
      }
      previousProcess = currentProcess;
    }

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
        currentProcess.stderr.on("data", function (/** @type {string} */ data) {
          commandOutput += data;
          stderrOutput += data;
        });
      currentProcess.stdout &&
        currentProcess.stdout.on("data", function (/** @type {string} */ data) {
          commandOutput += data;
          stdoutOutput += data;
        });

      currentProcess.on("close", async (/** @type {any} */ code) => {
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
 * @param {{prompt : string}} _
 */
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

/**
 * @param {WriteFileRequest} req
 * @param {{ cwd : string; }} _
 */
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

/**
 * @param {StartSpinnerRequest} req
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
  return spinnerId;
}

/**
 * @param {StopSpinnerRequest} req
 */
function runStopSpinner(req) {
  /** @type {{ spinnerId: string; completionText: string?; completionFn: string }} */
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

/**
 * @param {GlobRequest} req
 * @param {Set<string>} patternsToWatch
 */
async function runGlobNew(req, patternsToWatch) {
  const { pattern, options } = req.body.args[0];
  const cwd = path.resolve(...req.dir);
  const matchedPaths = await globby.globby(pattern, {
    ...options,
    stats: true,
    objectMode: true,
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

/**
 * @param {LogRequest} req
 */
async function runLogJob(req) {
  try {
    console.log(req.body.args[0].message);
    return null;
  } catch (e) {
    console.log(`Error performing env '${JSON.stringify(req.body)}'`);
    throw e;
  }
}

/**
 * @param {EnvRequest} req
 */
async function runEnvJob(req) {
  try {
    const expectedEnv = req.body.args[0];
    return process.env[expectedEnv] || null;
  } catch (e) {
    console.log(`Error performing env '${JSON.stringify(req.body)}'`);
    throw e;
  }
}

/**
 * @param {EncryptRequest} req
 */
async function runEncryptJob(req) {
  try {
    return cookie.sign(
      JSON.stringify(req.body.args[0].values, null, 0),
      req.body.args[0].secret
    );
  } catch (e) {
    throw {
      title: "BackendTask Encrypt Error",
      message: e.toString() + e.stack + "\n\n" + JSON.stringify(req, null, 2),
    };
  }
}

/**
 * @param {DecryptRequest} req
 */
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
      message: e.toString() + e.stack + "\n\n" + JSON.stringify(req, null, 2),
    };
  }
}

/**
 * @param {ElmApp} app
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
