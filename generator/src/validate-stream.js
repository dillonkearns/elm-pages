// source: https://www.30secondsofcode.org/js/s/typecheck-nodejs-streams/

/** @import {Duplex, Stream} from "node:stream" */

/**
 * @param {any} val
 * @returns {val is ReadableStream}
 */
export function isReadableStream(val) {
  return (
    val !== null &&
    typeof val === "object" &&
    typeof val.pipe === "function" &&
    typeof val._read === "function" &&
    typeof val._readableState === "object"
  );
}

/**
 * @param {any} val
 * @returns {val is WritableStream}
 */
export function isWritableStream(val) {
  return (
    val !== null &&
    typeof val === "object" &&
    typeof val.pipe === "function" &&
    typeof val._write === "function" &&
    typeof val._writableState === "object"
  );
}

/**
 * @param {any} val
 * @returns {val is Duplex}
 */
export function isDuplexStream(val) {
  return isReadableStream(val) && isWritableStream(val);
}
