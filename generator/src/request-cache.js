import * as path from "path";
import * as fsPromises from "fs/promises";
import { default as makeFetchHappenOriginal } from "make-fetch-happen";

/** @import {Pages_StaticHttp_Request, Pages_Internal_StaticHttpBody} from "./render.js" */

const defaultHttpCachePath = "./.elm-pages/http-cache";

/** @typedef {{kind: 'cache-response-path', value: string} | {kind: 'response-json', value: object}} Response */

/**
 * @param {string} mode
 * @param {Pages_StaticHttp_Request} rawRequest
 * @param {Record<string, unknown>} portsFile
 * @returns {Promise<Response>}
 */
export function lookupOrPerform(portsFile, mode, rawRequest) {
  const uniqueTimeId =
    Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  const timeStart = (message) => {
    !rawRequest.quiet && console.time(`${message} ${uniqueTimeId}`);
  };
  const timeEnd = (message) => {
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

    if (request.url === "elm-pages-internal://port") {
      try {
        const { input, portName } =
          /** @type {{input: unknown, portName: string}} */ (
            rawRequest.body.args[0]
          );

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
                    /** @type {Error} */ (portBackendTaskImportError).stack) ||
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
          const formData = partsToFormData(rawRequest.body.args[0]);
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
        const { body, bodyKind } = await readResponseBody(
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
        });
      } catch (error) {
        if (
          /** @type {NodeJS.ErrnoException} */ (error).code === "ECONNREFUSED"
        ) {
          resolve({
            kind: "response-json",
            value: { "elm-pages-internal-error": "NetworkError" },
          });
        } else if (
          /** @type {NodeJS.ErrnoException} */ (error).code === "ETIMEDOUT" ||
          /** @type {NodeJS.ErrnoException} */ (error).code ===
            "ERR_SOCKET_TIMEOUT"
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
 * @returns {object}
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
 * @param {Pages_StaticHttp_Request} elmRequest
 */
function toRequest(elmRequest) {
  const elmHeaders = Object.fromEntries(elmRequest.headers);
  let contentType = toContentType(elmRequest.body);
  let headers = { ...contentType, ...elmHeaders };
  return {
    url: elmRequest.url,
    method: elmRequest.method,
    headers,
    body: toBody(elmRequest.body),
  };
}
/**
 * @param {Pages_Internal_StaticHttpBody} body
 */
function toBody(body) {
  switch (body.tag) {
    case "EmptyBody": {
      return null;
    }
    case "StringBody": {
      return body.args[1];
    }
    case "BytesBody": {
      return Buffer.from(body.args[1], "base64");
    }
    case "JsonBody": {
      return JSON.stringify(body.args[0]);
    }
  }
}

/**
 * @param {Pages_Internal_StaticHttpBody} body
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
function partsToFormData(parts) {
  const formData = new FormData();
  for (const part of parts) {
    switch (part.type) {
      case "string":
        formData.append(part.name, part.value);
        break;
      case "bytes":
        formData.append(
          part.name,
          new Blob([Buffer.from(part.content, "base64")], {
            type: part.mimeType,
          })
        );
        break;
      case "bytesWithFilename":
        formData.append(
          part.name,
          new Blob([Buffer.from(part.content, "base64")], {
            type: part.mimeType,
          }),
          part.filename
        );
        break;
    }
  }
  return formData;
}

/**
 * Read the response body in the format expected by the Elm side.
 * Works with both make-fetch-happen responses (which have .buffer())
 * and standard fetch responses (which have .arrayBuffer()).
 * @param {{ text: () => any; }} response
 * @param {string} expectString
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
    return { body: buf.toString("base64"), bodyKind: "bytes" };
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
