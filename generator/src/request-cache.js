const path = require("path");
const fetch = require("node-fetch");
const objectHash = require("object-hash");
const kleur = require("kleur");

/**
 * To cache HTTP requests on disk with quick lookup and insertion, we store the hashed request.
 * This uses SHA1 hashes. They are uni-directional hashes, which works for this use case. Most importantly,
 * they're unique enough and can be expressed in a case-insensitive way so it works on Windows filesystems.
 * And they are 40 hex characters, so the length won't be too long no matter what the request payload.
 * @param {Object} request
 */
function requestToString(request) {
  return objectHash(request);
}
/**
 * @param {Object} request
 */
function fullPath(portsHash, request, hasFsAccess) {
  const requestWithPortHash =
    request.url === "elm-pages-internal://port"
      ? { portsHash, ...request }
      : request;
  if (hasFsAccess) {
    return path.join(
      process.cwd(),
      // TODO use parameter or something other than global for this `global.isRunningGenerator` condition
      global.isRunningGenerator ? "../.elm-pages" : ".elm-pages",
      "http-response-cache",
      requestToString(requestWithPortHash)
    );
  } else {
    return path.join("/", requestToString(requestWithPortHash));
  }
}

/**
 * @param {string} mode
 * @param {{url: string;headers: {[x: string]: string;};method: string;body: Body;}} rawRequest
 * @returns {Promise<string>}
 * @param {string} portsFile
 * @param {boolean} hasFsAccess
 */
function lookupOrPerform(portsFile, mode, rawRequest, hasFsAccess, useCache) {
  const { fs } = require("./request-cache-fs.js")(hasFsAccess);
  return new Promise(async (resolve, reject) => {
    const request = toRequest(rawRequest);
    const portsHash = (portsFile && portsFile.match(/-([^-]+)\.js$/)[1]) || "";
    const responsePath = fullPath(portsHash, request, hasFsAccess);

    // TODO check cache expiration time and delete and go to else if expired
    if (useCache && (await checkFileExists(fs, responsePath))) {
      // console.log("Skipping request, found file.");
      resolve(responsePath);
    } else {
      let portDataSource = {};
      let portDataSourceImportError = null;
      try {
        if (portsFile === undefined) {
          throw "missing";
        }
        const portDataSourcePath = path.resolve(portsFile);
        // On Windows, we need cannot use paths directly and instead must use a file:// URL.
        // portDataSource = await require(url.pathToFileURL(portDataSourcePath).href);
        portDataSource = require(portDataSourcePath);
      } catch (e) {
        portDataSourceImportError = e;
      }

      if (request.url === "elm-pages-internal://port") {
        try {
          const { input, portName } = rawRequest.body.args[0];

          if (!portDataSource[portName]) {
            if (portDataSourceImportError === null) {
              throw `DataSource.Port.send "${portName}" was called, but I couldn't find a function with that name in the port definitions file. Is it exported correctly?`;
            } else if (portDataSourceImportError === "missing") {
              throw `DataSource.Port.send "${portName}" was called, but I couldn't find the port definitions file. Be sure to create a 'port-data-source.ts' or 'port-data-source.js' file and maybe restart the dev server.`;
            } else {
              throw `DataSource.Port.send "${portName}" was called, but I couldn't import the port definitions file, because of this exception: \`${portDataSourceImportError}\` Are there syntax errors or expections thrown during import?`;
            }
          } else if (typeof portDataSource[portName] !== "function") {
            throw `DataSource.Port.send "${portName}" was called, but it is not a function. Be sure to export a function with that name from port-data-source.js`;
          }
          await fs.promises.writeFile(
            responsePath,
            JSON.stringify(jsonResponse(await portDataSource[portName](input)))
          );
          resolve(responsePath);
        } catch (error) {
          console.trace(error);
          reject({
            title: "DataSource.Port Error",
            message: error.toString(),
          });
        }
      } else {
        try {
          console.time(`fetch ${request.url}`);
          const response = await fetch(request.url, {
            method: request.method,
            body: request.body,
            headers: {
              "User-Agent": "request",
              ...request.headers,
            },
          });

          console.timeEnd(`fetch ${request.url}`);
          const expectString = request.headers["elm-pages-internal"];

          if (response.ok || expectString === "ExpectResponse") {
            let body;
            let bodyKind;
            if (expectString === "ExpectJson") {
              body = await response.json();
              bodyKind = "json";
            } else if (
              expectString === "ExpectBytes" ||
              expectString === "ExpectBytesResponse"
            ) {
              bodyKind = "bytes";
              const arrayBuffer = await response.arrayBuffer();
              body = Buffer.from(arrayBuffer).toString("base64");
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

            await fs.promises.writeFile(
              responsePath,
              JSON.stringify({
                headers: Object.fromEntries(response.headers.entries()),
                statusCode: response.status,
                body: body,
                bodyKind,
                url: response.url,
                statusText: response.statusText,
              })
            );

            resolve(responsePath);
          } else {
            console.log("@@@ request-cache1 bad HTTP response");
            reject({
              title: "DataSource.Http Error",
              message: `${kleur
                .yellow()
                .underline(request.url)} Bad HTTP response ${response.status} ${
                response.statusText
              }
`,
            });
          }
        } catch (error) {
          console.trace("@@@ request-cache2 HTTP error", error);
          reject({
            title: "DataSource.Http Error",
            message: `${kleur
              .yellow()
              .underline(request.url)} ${error.toString()}
`,
          });
        }
      }
    }
  });
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
 * @param {string} file
 */
function checkFileExists(fs, file) {
  return fs.promises
    .access(file, fs.constants.F_OK)
    .then(() => true)
    .catch(() => false);
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
    case "JsonBody": {
      return { "Content-Type": "application/json" };
    }
  }
}

/** @typedef { { tag: 'EmptyBody'} | { tag: 'StringBody'; args: [string, string] } | {tag: 'JsonBody'; args: [ Object ] } } Body  */
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

module.exports = { lookupOrPerform };
