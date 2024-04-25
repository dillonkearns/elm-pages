// source: https://www.30secondsofcode.org/js/s/typecheck-nodejs-streams/

export function isReadableStream(val) {
  return (
    val !== null &&
    typeof val === "object" &&
    typeof val.pipe === "function" &&
    typeof val._read === "function" &&
    typeof val._readableState === "object"
  );
}

export function isWritableStream(val) {
  return (
    val !== null &&
    typeof val === "object" &&
    typeof val.pipe === "function" &&
    typeof val._write === "function" &&
    typeof val._writableState === "object"
  );
}

export function isDuplexStream(val) {
  return isReadableStream(val) && isWritableStream(val);
}
