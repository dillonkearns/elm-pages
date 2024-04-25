import * as path from "path";
import * as fsPromises from "fs/promises";
import * as kleur from "kleur/colors";
import { default as makeFetchHappenOriginal } from "make-fetch-happen";

const defaultHttpCachePath = "./.elm-pages/http-cache";

/** @typedef {{kind: 'cache-response-path', value: string} | {kind: 'response-json', value: JSON}} Response */

/**
 * @param {string} mode
 * @param {{url: string;headers: {[x: string]: string;};method: string;body: Body; }} rawRequest
 * @param {Record<string, unknown>} portsFile
 * @param {boolean} hasFsAccess
 * @returns {Promise<Response>}
 */
export function lookupOrPerform(
  portsFile,
  mode,
  rawRequest,
  hasFsAccess,
  useCache
) {
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
          !rawRequest.quiet &&
            console.time(`BackendTask.Custom.run "${portName}"`);
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
          !rawRequest.quiet &&
            console.timeEnd(`BackendTask.Custom.run "${portName}"`);
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
        !rawRequest.quiet && console.time(`fetch ${request.url}`);
        const response = await safeFetch(makeFetchHappen, request.url, {
          method: request.method,
          body: request.body,
          headers: {
            "User-Agent": "request",
            ...request.headers,
          },
          ...rawRequest.cacheOptions,
        });

        !rawRequest.quiet && console.timeEnd(`fetch ${request.url}`);
        const expectString = request.headers["elm-pages-internal"];

        let body;
        let bodyKind;
        if (expectString === "ExpectJson") {
          try {
            body = await response.buffer();
            body = JSON.parse(body.toString("utf-8"));
            bodyKind = "json";
          } catch (error) {
            body = body.toString("utf8");
            bodyKind = "string";
          }
        } else if (
          expectString === "ExpectBytes" ||
          expectString === "ExpectBytesResponse"
        ) {
          body = await response.buffer();
          try {
            body = body.toString("base64");
            bodyKind = "bytes";
          } catch (e) {
            body = body.toString("utf8");
            bodyKind = "string";
          }
        } else if (expectString === "ExpectWhatever") {
          bodyKind = "whatever";
          body = null;
        } else if (
          expectString === "ExpectResponse" ||
          expectString === "ExpectString"
        ) {
          bodyKind = "string";
          body = await response.text();
        } else {
          throw `Unexpected expectString ${expectString}`;
        }

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
    body: toBody(elmRequest.body),
  };
}
/**
 * @param {Body} body
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

/** @typedef { { tag: 'EmptyBody'} |{ tag: 'BytesBody'; args: [string, string] } |  { tag: 'StringBody'; args: [string, string] } | {tag: 'JsonBody'; args: [ Object ] } } Body  */
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
