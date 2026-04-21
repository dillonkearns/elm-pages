import * as path from "path";
import * as fsPromises from "fs/promises";
import * as kleur from "kleur/colors";
import { default as makeFetchHappenOriginal } from "make-fetch-happen";
import * as parallelWorkerPool from "./parallel-worker-pool.js";

const defaultHttpCachePath = "./.elm-pages/http-cache";

/** @typedef {{kind: 'cache-response-path', value: string} | {kind: 'response-json', value: JSON}} Response */

/**
 * @param {string} mode
 * @param {{url: string; headers: {[x: string]: string;}; method: string; body: Body; quiet: boolean; }} rawRequest
 * @param {Record<string, unknown>} portsFile
 * @returns {Promise<Response>}
 */
export function lookupOrPerform(portsFile, mode, rawRequest) {
  const uniqueTimeId =
    Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  const timeStart = (/** @type {string} */ message) => {
    !rawRequest.quiet && console.time(`${message} ${uniqueTimeId}`);
  };
  const timeEnd = (/** @type {string} */ message) => {
    !rawRequest.quiet && console.timeEnd(`${message} ${uniqueTimeId}`);
  };
  const makeFetchHappen = makeFetchHappenOriginal.defaults({
    cache: mode === "build" ? "no-cache" : "default",
  });
  return new Promise(async (resolve, reject) => {
    const request = toRequest(rawRequest);

    let portBackendTask = portsFile;
    let portBackendTaskImportError = null;
    try {
      if (portsFile === undefined) {
        throw "missing";
      }
    } catch (e) {
      portBackendTaskImportError = e;
    }

    if (
      request.url.startsWith("elm-pages-internal://parallel-spawn-worker/")
    ) {
      // BackendTask.Parallel.worker — bring up (or rebuild) an Elm-in-
      // worker sub-pool for this module and ship it the one-time shared
      // payload. Resolves with empty bytes (the Elm side decodes
      // `Bytes.Decode.succeed (Worker workerModule)`).
      const workerModule = request.url.substring(
        "elm-pages-internal://parallel-spawn-worker/".length
      );
      try {
        const sharedBytes = rawRequest.__rawBytes || Buffer.alloc(0);
        timeStart(`BackendTask.Parallel.worker "${workerModule}"`);
        try {
          await parallelWorkerPool.spawnElmWorkerPool({
            workerModule,
            sharedBytes,
          });
        } finally {
          timeEnd(`BackendTask.Parallel.worker "${workerModule}"`);
        }
        resolve({
          kind: "response-json",
          value: { bodyKind: "bytes", body: null },
          rawBytes: Buffer.alloc(0),
        });
      } catch (error) {
        reject({
          title: "BackendTask.Parallel.worker Error",
          message: error instanceof Error ? error.message : String(error),
        });
      }
    } else if (
      request.url.startsWith("elm-pages-internal://parallel-worker-task/")
    ) {
      // BackendTask.Parallel.runOn — dispatch one task input to a free
      // worker in the sub-pool for the given module. Resolves with the
      // bytes the worker handed back via `sendResult`.
      const workerModule = request.url.substring(
        "elm-pages-internal://parallel-worker-task/".length
      );
      try {
        const inputBytes = rawRequest.__rawBytes || Buffer.alloc(0);
        timeStart(`BackendTask.Parallel.runOn "${workerModule}"`);
        let outputBuffer;
        try {
          const result = await parallelWorkerPool.dispatchElmTask({
            workerModule,
            inputBytes,
          });
          outputBuffer = Buffer.isBuffer(result)
            ? result
            : Buffer.from(
                result.buffer,
                result.byteOffset,
                result.byteLength
              );
        } catch (dispatchError) {
          timeEnd(`BackendTask.Parallel.runOn "${workerModule}"`);
          reject({
            title: "BackendTask.Parallel.runOn Error",
            message:
              dispatchError instanceof Error
                ? dispatchError.message
                : String(dispatchError),
          });
          return;
        }
        timeEnd(`BackendTask.Parallel.runOn "${workerModule}"`);
        resolve({
          kind: "response-json",
          value: { bodyKind: "bytes", body: null },
          rawBytes: outputBuffer,
        });
      } catch (error) {
        reject({
          title: "BackendTask.Parallel.runOn Error",
          message: error instanceof Error ? error.message : String(error),
        });
      }
    } else if (
      request.url.startsWith("elm-pages-internal://parallel-port-bytes/")
    ) {
      // BackendTask.Parallel.run — same Bytes-in/Bytes-out wire as
      // Custom.runBytes, but the port function runs in a worker thread
      // pulled from the persistent pool. Port name follows the URL prefix.
      const portName = request.url.substring(
        "elm-pages-internal://parallel-port-bytes/".length
      );
      try {
        const inputBytes = rawRequest.__rawBytes || Buffer.alloc(0);
        const context = {
          cwd: path.resolve(...rawRequest.dir),
          quiet: rawRequest.quiet,
          env: { ...process.env, ...rawRequest.env },
        };

        timeStart(`BackendTask.Parallel.run "${portName}"`);
        let outputBuffer;
        try {
          const result = await parallelWorkerPool.dispatch(
            portName,
            inputBytes,
            context
          );
          // Worker returns Buffer, but structured-clone across the thread
          // boundary may surface it as Uint8Array. Normalize to Buffer
          // (zero-copy when possible) before handing to render.js.
          outputBuffer = Buffer.isBuffer(result)
            ? result
            : Buffer.from(
                result.buffer,
                result.byteOffset,
                result.byteLength
              );
        } catch (dispatchError) {
          timeEnd(`BackendTask.Parallel.run "${portName}"`);
          reject({
            title: "BackendTask.Parallel.run Error",
            message:
              dispatchError instanceof Error
                ? dispatchError.message
                : String(dispatchError),
          });
          return;
        }
        timeEnd(`BackendTask.Parallel.run "${portName}"`);

        resolve({
          kind: "response-json",
          value: { bodyKind: "bytes", body: null },
          rawBytes: outputBuffer,
        });
      } catch (error) {
        reject({
          title: "BackendTask.Parallel.run Error",
          message: error instanceof Error ? error.message : String(error),
        });
      }
    } else if (
      request.url === "elm-pages-internal://parallel-worker-init-shared"
    ) {
      // BackendTask.Parallel.initShared — primitive used by an Elm script
      // running inside a parallel worker thread to receive its one-time
      // shared payload from the parent thread.
      //
      // B.1 stub: returns empty bytes so the caller's decoder can be
      // exercised. The real handler in B.3 will block until the parent
      // worker pool delivers the actual shared payload through the
      // worker-side bridge in parallel-worker.js.
      resolve({
        kind: "response-json",
        value: { bodyKind: "bytes", body: null },
        rawBytes: Buffer.alloc(0),
      });
    } else if (
      request.url === "elm-pages-internal://parallel-worker-receive-task"
    ) {
      // BackendTask.Parallel.receiveTask — primitive used by an Elm script
      // running inside a parallel worker thread to receive the next task's
      // input bytes from the parent thread.
      //
      // B.1 stub: returns a 4-byte big-endian u32 sentinel (42) so the
      // smoke test in test-scripts/ can exercise the plumbing end-to-end.
      // The real handler in B.3 will block until the parent dispatches a
      // task via parallel-worker-pool's elm-script branch.
      const stub = Buffer.alloc(4);
      stub.writeUInt32BE(42, 0);
      resolve({
        kind: "response-json",
        value: { bodyKind: "bytes", body: null },
        rawBytes: stub,
      });
    } else if (
      request.url === "elm-pages-internal://parallel-worker-send-result"
    ) {
      // BackendTask.Parallel.sendResult — primitive used by an Elm script
      // running inside a parallel worker thread to hand a task result back
      // to the parent.
      //
      // B.1 stub: discards the input bytes and resolves with empty bytes
      // (the Elm side decodes `Bytes.Decode.succeed ()`). The real handler
      // in B.3 will route the bytes back to the awaiting `runOn` promise
      // on the parent.
      resolve({
        kind: "response-json",
        value: { bodyKind: "bytes", body: null },
        rawBytes: Buffer.alloc(0),
      });
    } else if (request.url.startsWith("elm-pages-internal://port-bytes/")) {
      // Bytes-in / Bytes-out variant used by BackendTask.Custom.runBytes.
      // The port name is encoded in the URL path; the input Bytes arrive via
      // the port sidecar as `rawRequest.__rawBytes`; the response is a raw
      // Buffer returned directly (no JSON envelope).
      const portName = request.url.substring(
        "elm-pages-internal://port-bytes/".length
      );
      try {
        const inputBytes = rawRequest.__rawBytes || Buffer.alloc(0);

        if (portBackendTask === null) {
          reject({
            title: "BackendTask.Custom.runBytes Error",
            message:
              "No custom-backend-task file found. Create a custom-backend-task.js or .ts file at the project root.",
          });
          return;
        }
        if (portBackendTask && portBackendTask.__internalElmPagesError) {
          reject({
            title: "BackendTask.Custom.runBytes Error",
            message:
              "Error importing custom-backend-task file: " +
              portBackendTask.__internalElmPagesError,
          });
          return;
        }
        if (!portBackendTask[portName]) {
          reject({
            title: "BackendTask.Custom.runBytes Error",
            message: `No export named \`${portName}\` found in custom-backend-task file.`,
          });
          return;
        }
        if (typeof portBackendTask[portName] !== "function") {
          reject({
            title: "BackendTask.Custom.runBytes Error",
            message: `Export \`${portName}\` is not a function (found ${typeof portBackendTask[
              portName
            ]}).`,
          });
          return;
        }

        timeStart(`BackendTask.Custom.runBytes "${portName}"`);
        const context = {
          cwd: path.resolve(...rawRequest.dir),
          quiet: rawRequest.quiet,
          env: { ...process.env, ...rawRequest.env },
        };

        let result;
        try {
          result = await portBackendTask[portName](inputBytes, context);
        } catch (portCallError) {
          timeEnd(`BackendTask.Custom.runBytes "${portName}"`);
          reject({
            title: "BackendTask.Custom.runBytes Error",
            message: `Port \`${portName}\` threw: ${
              portCallError instanceof Error
                ? portCallError.message
                : String(portCallError)
            }`,
          });
          return;
        }
        timeEnd(`BackendTask.Custom.runBytes "${portName}"`);

        // Accept Buffer, Uint8Array, or ArrayBuffer; reject anything else.
        let outputBuffer;
        if (Buffer.isBuffer(result)) {
          outputBuffer = result;
        } else if (result instanceof Uint8Array) {
          outputBuffer = Buffer.from(
            result.buffer,
            result.byteOffset,
            result.byteLength
          );
        } else if (result instanceof ArrayBuffer) {
          outputBuffer = Buffer.from(result);
        } else {
          reject({
            title: "BackendTask.Custom.runBytes Error",
            message: `Port \`${portName}\` must return Bytes (Buffer, Uint8Array, or ArrayBuffer). Got: ${typeof result}`,
          });
          return;
        }

        resolve({
          kind: "response-json",
          value: { bodyKind: "bytes", body: null },
          rawBytes: outputBuffer,
        });
      } catch (error) {
        reject({
          title: "BackendTask.Custom.runBytes Error",
          message: error instanceof Error ? error.message : String(error),
        });
      }
    } else if (request.url === "elm-pages-internal://port") {
      try {
        const { input, portName } = rawRequest.body.args[0];

        if (portBackendTask === null) {
          resolve({
            kind: "response-json",
            value: jsonResponse({
              "elm-pages-internal-error": "MissingCustomBackendTaskFile",
            }),
          });
        } else if (portBackendTask && portBackendTask.__internalElmPagesError) {
          resolve({
            kind: "response-json",
            value: jsonResponse({
              "elm-pages-internal-error": "ErrorInCustomBackendTaskFile",
              error: portBackendTask.__internalElmPagesError,
            }),
          });
        } else if (portBackendTask && !portBackendTask[portName]) {
          if (portBackendTaskImportError === null) {
            resolve({
              kind: "response-json",
              value: jsonResponse({
                "elm-pages-internal-error": "CustomBackendTaskNotDefined",
              }),
            });
          } else if (portBackendTaskImportError === "missing") {
            resolve({
              kind: "response-json",
              value: jsonResponse({
                "elm-pages-internal-error": "MissingCustomBackendTaskFile",
              }),
            });
          } else {
            resolve({
              kind: "response-json",
              value: jsonResponse({
                "elm-pages-internal-error": "ErrorInCustomBackendTaskFile",
                error:
                  (portBackendTaskImportError &&
                    portBackendTaskImportError.stack) ||
                  "",
              }),
            });
          }
        } else if (typeof portBackendTask[portName] !== "function") {
          resolve({
            kind: "response-json",
            value: jsonResponse({
              "elm-pages-internal-error": "ExportIsNotFunction",
              error: typeof portBackendTask[portName],
            }),
          });
        } else {
          timeStart(`BackendTask.Custom.run "${portName}"`);
          let context = {
            cwd: path.resolve(...rawRequest.dir),
            quiet: rawRequest.quiet,
            env: { ...process.env, ...rawRequest.env },
          };
          try {
            resolve({
              kind: "response-json",
              value: jsonResponse(
                toElmJson(await portBackendTask[portName](input, context))
              ),
            });
          } catch (portCallError) {
            if (portCallError instanceof Error) {
              resolve({
                kind: "response-json",
                value: jsonResponse({
                  "elm-pages-internal-error": "NonJsonException",
                  error: portCallError.message,
                  stack: portCallError.stack || null,
                }),
              });
            }
            try {
              resolve({
                kind: "response-json",
                value: jsonResponse({
                  "elm-pages-internal-error": "CustomBackendTaskException",
                  error: JSON.parse(JSON.stringify(portCallError, null, 0)),
                }),
              });
            } catch (jsonDecodeError) {
              resolve({
                kind: "response-json",
                value: jsonResponse({
                  "elm-pages-internal-error": "NonJsonException",
                  error: portCallError.toString(),
                }),
              });
            }
          }
          timeEnd(`BackendTask.Custom.run "${portName}"`);
        }
      } catch (error) {
        console.trace(error);
        reject({
          title: "BackendTask.Custom Error",
          message: error.toString(),
        });
      }
    } else {
      try {
        timeStart(`fetch ${request.url}`);

        let response;
        if (rawRequest.body.tag === "MultipartBody") {
          // Use built-in fetch with FormData for streaming multipart
          // bodies — no intermediate Buffer, and the boundary is
          // generated automatically by undici.
          const formData = partsToFormData(rawRequest.body.args[0], rawRequest.__multipartBytes);
          const elmHeaders = Object.fromEntries(rawRequest.headers);
          response = await fetch(request.url, {
            method: request.method,
            body: formData,
            headers: {
              "User-Agent": "request",
              ...elmHeaders,
            },
          });
        } else {
          response = await safeFetch(makeFetchHappen, request.url, {
            method: request.method,
            body: request.body,
            headers: {
              "User-Agent": "request",
              ...request.headers,
            },
            ...rawRequest.cacheOptions,
          });
        }

        timeEnd(`fetch ${request.url}`);
        const { body, bodyKind, rawBytes } = await readResponseBody(
          response,
          request.headers["elm-pages-internal"]
        );

        resolve({
          kind: "response-json",
          value: {
            headers: Object.fromEntries(response.headers.entries()),
            statusCode: response.status,
            body,
            bodyKind,
            url: response.url,
            statusText: response.statusText,
          },
          rawBytes: rawBytes || null,
        });
      } catch (error) {
        if (error.code === "ECONNREFUSED") {
          resolve({
            kind: "response-json",
            value: { "elm-pages-internal-error": "NetworkError" },
          });
        } else if (
          error.code === "ETIMEDOUT" ||
          error.code === "ERR_SOCKET_TIMEOUT"
        ) {
          resolve({
            kind: "response-json",
            value: { "elm-pages-internal-error": "Timeout" },
          });
        } else {
          console.trace("elm-pages unhandled HTTP error", error);
          resolve({
            kind: "response-json",
            value: { "elm-pages-internal-error": "NetworkError" },
          });
        }
      }
    }
  });
}

/**
 * @param {unknown} obj
 * @returns {JSON}
 */
function toElmJson(obj) {
  if (Array.isArray(obj)) {
    return obj.map(toElmJson);
  } else if (typeof obj === "object") {
    for (let key in obj) {
      const value = obj[key];
      if (typeof value === "undefined") {
        obj[key] = null;
      } else if (value instanceof Date) {
        obj[key] = {
          "__elm-pages-normalized__": {
            kind: "Date",
            value: Math.floor(value.getTime()),
          },
        };
        // } else if (value instanceof Object) {
        //   toElmJson(obj);
      }
    }
  }
  return obj;
}

/**
 * @param {{url: string; headers: {[x: string]: string}; method: string; body: Body } } elmRequest
 */
function toRequest(elmRequest) {
  const elmHeaders = Object.fromEntries(elmRequest.headers);
  let contentType = toContentType(elmRequest.body);
  let headers = { ...contentType, ...elmHeaders };
  return {
    url: elmRequest.url,
    method: elmRequest.method,
    headers,
    body: toBody(elmRequest.body, elmRequest.__rawBytes),
  };
}
/**
 * @param {Body} body
 */
/**
 * @param {Body} body
 * @param {Buffer} [rawBytes] - Raw bytes from port, used instead of base64 for BytesBody
 */
function toBody(body, rawBytes) {
  switch (body.tag) {
    case "EmptyBody": {
      return null;
    }
    case "StringBody": {
      return body.args[1];
    }
    case "BytesBody": {
      // Prefer raw bytes from port if available (avoids base64 decode)
      return rawBytes || Buffer.from(body.args[1], "base64");
    }
    case "JsonBody": {
      return JSON.stringify(body.args[0]);
    }
  }
}

/**
 * @param {Body} body
 * @returns Object
 */
function toContentType(body) {
  switch (body.tag) {
    case "EmptyBody": {
      return {};
    }
    case "StringBody": {
      return { "Content-Type": body.args[0] };
    }
    case "BytesBody": {
      return { "Content-Type": body.args[0] };
    }
    case "JsonBody": {
      return { "Content-Type": "application/json" };
    }
  }
}

/**
 * Convert structured parts from Elm into a FormData instance.
 * @param {Array<{type: string, name: string, value?: string, mimeType?: string, filename?: string, content?: string}>} parts
 * @returns {FormData}
 */
function partsToFormData(parts, multipartBytes) {
  const formData = new FormData();
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    switch (part.type) {
      case "string":
        formData.append(part.name, part.value);
        break;
      case "bytes": {
        const buf = multipartBytes?.get(i);
        if (!buf) {
          throw new Error(`Missing raw bytes for multipart part ${i}`);
        }
        formData.append(
          part.name,
          new Blob([buf], {
            type: part.mimeType,
          })
        );
        break;
      }
      case "bytesWithFilename": {
        const buf = multipartBytes?.get(i);
        if (!buf) {
          throw new Error(`Missing raw bytes for multipart part ${i}`);
        }
        formData.append(
          part.name,
          new Blob([buf], {
            type: part.mimeType,
          }),
          part.filename
        );
        break;
      }
    }
  }
  return formData;
}

/**
 * Read the response body in the format expected by the Elm side.
 * Works with both make-fetch-happen responses (which have .buffer())
 * and standard fetch responses (which have .arrayBuffer()).
 */
async function readResponseBody(response, expectString) {
  if (expectString === "ExpectJson") {
    const buf = await responseBuffer(response);
    try {
      return { body: JSON.parse(buf.toString("utf-8")), bodyKind: "json" };
    } catch (error) {
      return { body: buf.toString("utf8"), bodyKind: "string" };
    }
  } else if (
    expectString === "ExpectBytes" ||
    expectString === "ExpectBytesResponse"
  ) {
    const buf = await responseBuffer(response);
    return { body: null, bodyKind: "bytes", rawBytes: buf };
  } else if (expectString === "ExpectWhatever") {
    return { body: null, bodyKind: "whatever" };
  } else if (
    expectString === "ExpectResponse" ||
    expectString === "ExpectString"
  ) {
    return { body: await response.text(), bodyKind: "string" };
  } else {
    throw `Unexpected expectString ${expectString}`;
  }
}

/**
 * Get a Buffer from a response, supporting both make-fetch-happen
 * (.buffer()) and standard fetch (.arrayBuffer()) responses.
 */
async function responseBuffer(response) {
  if (typeof response.buffer === "function") {
    return response.buffer();
  }
  return Buffer.from(await response.arrayBuffer());
}

/** @typedef { { tag: 'EmptyBody'} |{ tag: 'BytesBody'; args: [string, string] } |  { tag: 'StringBody'; args: [string, string] } | {tag: 'JsonBody'; args: [ Object ] } | {tag: 'MultipartBody'; args: [ Array ] } } Body  */
function requireUncached(mode, filePath) {
  if (mode === "dev-server") {
    // for the build command, we can skip clearing the cache because it won't change while the build is running
    // in the dev server, we want to clear the cache to get a the latest code each time it runs
    delete require.cache[require.resolve(filePath)];
  }
  return require(filePath);
}

/**
 * @param {unknown} json
 */
function jsonResponse(json) {
  return { bodyKind: "json", body: json };
}

async function safeFetch(makeFetchHappen, url, options) {
  const { cachePath, ...optionsWithoutCachePath } = options;
  const cachePathWithDefault = cachePath || defaultHttpCachePath;
  if (await canAccess(cachePathWithDefault)) {
    return await makeFetchHappen(url, {
      cachePath: cachePathWithDefault,
      ...options,
    });
  } else {
    return await makeFetchHappen(url, {
      cache: "no-store",
      ...optionsWithoutCachePath,
    });
  }
}

async function canAccess(filePath) {
  try {
    await fsPromises.access(
      filePath,
      fsPromises.constants.R_OK | fsPromises.constants.W_OK
    );
    return true;
  } catch {
    return false;
  }
}
