const path = require("path");
const undici = require("undici");
const fs = require("fs");
const objectHash = require("object-hash");

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
function fullPath(request) {
  return path.join(
    process.cwd(),
    ".elm-pages",
    "http-response-cache",
    requestToString(request)
  );
}

/**
 * @param {{url: string; headers: {[x: string]: string}; method: string; body: Body } } rawRequest
 * @returns {Promise<string>}
 */
function lookupOrPerform(rawRequest) {
  return new Promise((resolve, reject) => {
    const request = toRequest(rawRequest);
    const responsePath = fullPath(request);

    if (fs.existsSync(responsePath)) {
      // console.log("Skipping request, found file.");
      resolve(responsePath);
    } else {
      undici
        .stream(
          request.url,
          {
            method: request.method,
            body: request.body,
            headers: {
              "User-Agent": "request",
              ...request.headers,
            },
          },
          (response) => {
            const writeStream = fs.createWriteStream(responsePath);
            writeStream.on("finish", async () => {
              resolve(responsePath);
            });

            return writeStream;
          }
        )
        .catch(reject);
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

module.exports = { lookupOrPerform };
