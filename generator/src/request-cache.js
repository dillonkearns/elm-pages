const path = require("path");
const undici = require("undici");
const objectHash = require("object-hash");
const kleur = require("kleur");
const cookie = require("cookie-signature");

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
function fullPath(request, hasFsAccess) {
  if (hasFsAccess) {
    return path.join(
      process.cwd(),
      ".elm-pages",
      "http-response-cache",
      requestToString(request)
    );
  } else {
    return path.join("/", requestToString(request));
  }
}

/**
 * @param {string} mode
 * @param {{url: string; headers: {[x: string]: string}; method: string; body: Body } } rawRequest
 * @returns {Promise<string>}
 */
function lookupOrPerform(mode, rawRequest, hasFsAccess) {
  const { fs } = require("./request-cache-fs.js")(hasFsAccess);
  return new Promise(async (resolve, reject) => {
    const request = toRequest(rawRequest);
    const responsePath = fullPath(request, hasFsAccess);

    // TODO check cache expiration time and delete and go to else if expired
    if (await checkFileExists(fs, responsePath)) {
      // console.log("Skipping request, found file.");
      resolve(responsePath);
    } else {
      let portDataSource = {};
      let portDataSourceFound = false;
      try {
        portDataSource = requireUncached(
          mode,
          path.join(process.cwd(), "port-data-source.js")
        );
        portDataSourceFound = true;
      } catch (e) {}

      if (request.url === "port://encrypt") {
        try {
          await fs.promises.writeFile(
            responsePath,
            JSON.stringify(
              cookie.sign(
                JSON.stringify(rawRequest.body.args[0].values, null, 0),
                rawRequest.body.args[0].secret
              )
            )
          );
          resolve(responsePath);
        } catch (e) {
          reject({
            title: "DataSource.Port Error",
            message:
              e.toString() +
              e.stack +
              "\n\n" +
              JSON.stringify(rawRequest, null, 2),
          });
        }
      } else if (request.url === "port://decrypt") {
        try {
          // TODO if unsign returns `false`, need to have an `Err` in Elm because decryption failed
          const signed = tryDecodeCookie(
            rawRequest.body.args[0].input,
            rawRequest.body.args[0].secrets
          );

          await fs.promises.writeFile(responsePath, signed || "null");
          resolve(responsePath);
        } catch (e) {
          reject({
            title: "DataSource.Port Error",
            message:
              e.toString() +
              e.stack +
              "\n\n" +
              JSON.stringify(rawRequest, null, 2),
          });
        }
      } else if (request.url.startsWith("port://")) {
        try {
          const portName = request.url.replace(/^port:\/\//, "");
          // console.time(JSON.stringify(request.url));
          if (!portDataSource[portName]) {
            if (portDataSourceFound) {
              throw `DataSource.Port.send "${portName}" is not defined. Be sure to export a function with that name from port-data-source.js`;
            } else {
              throw `DataSource.Port.send "${portName}" was called, but I couldn't find the port definitions file 'port-data-source.js'.`;
            }
          } else if (typeof portDataSource[portName] !== "function") {
            throw `DataSource.Port.send "${portName}" is not a function. Be sure to export a function with that name from port-data-source.js`;
          }
          await fs.promises.writeFile(
            responsePath,
            JSON.stringify(
              await portDataSource[portName](rawRequest.body.args[0])
            )
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
          const response = await undici.fetch(request.url, {
            method: request.method,
            body: request.body,
            headers: {
              "User-Agent": "request",
              ...request.headers,
            },
          });
          const expectString = request.headers["elm-pages-internal"];

          if (response.ok || expectString === "ExpectResponse") {
            let body;
            if (expectString === "ExpectJson") {
              body = await response.json();
            } else {
              body = await response.text();
            }
            await fs.promises.writeFile(
              responsePath,
              JSON.stringify({
                headers: Object.fromEntries(response.headers.entries()),
                statusCode: response.status,
                body: body,
                url: response.url,
                statusText: response.statusText,
              })
            );

            resolve(responsePath);
          } else {
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

module.exports = { lookupOrPerform };
