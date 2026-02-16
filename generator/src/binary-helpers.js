/**
 * Convert binary payloads to a Node.js Buffer using the exact byte range.
 *
 * This avoids including unrelated bytes when the payload is a view into a
 * larger ArrayBuffer (for example Uint8Array subarrays).
 *
 * @param {Buffer | Uint8Array | DataView | ArrayBuffer} bytes
 * @returns {Buffer}
 */
export function toExactBuffer(bytes) {
  if (Buffer.isBuffer(bytes)) {
    return bytes;
  }

  if (bytes instanceof ArrayBuffer) {
    return Buffer.from(bytes);
  }

  if (ArrayBuffer.isView(bytes)) {
    return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }

  throw new Error("Unsupported binary payload type.");
}
