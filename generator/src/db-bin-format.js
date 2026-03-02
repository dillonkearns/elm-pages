/**
 * db.bin binary format utilities.
 *
 * Offset 0:  4 bytes  - Magic: "EPDB" (0x45 0x50 0x44 0x42)
 * Offset 4:  2 bytes  - Format version (uint16 BE) = 1
 * Offset 6:  4 bytes  - Schema version counter (uint32 BE)
 * Offset 10: 32 bytes - Schema hash (SHA-256 raw bytes)
 * Offset 42: N bytes  - Wire3-encoded Db data
 */

export const DB_MAGIC = Buffer.from("EPDB", "ascii");
export const DB_FORMAT_VERSION = 1;
export const DB_HEADER_SIZE = 4 + 2 + 4 + 32; // magic + format_version + schema_version + hash

/**
 * Parse a db.bin buffer.
 * @param {Buffer} fileContents
 * @returns {{ formatVersion: number, schemaVersion: number, schemaHashHex: string, wire3Data: Buffer }}
 */
export function parseDbBinHeader(fileContents) {
  if (fileContents.length < DB_HEADER_SIZE) {
    throw {
      title: "db.bin is corrupt",
      message:
        "The db.bin file is too small to contain a valid header. Delete db.bin (and db.lock if present) to start fresh.",
    };
  }

  if (!fileContents.subarray(0, 4).equals(DB_MAGIC)) {
    throw {
      title: "db.bin is corrupt",
      message:
        "The db.bin file has invalid magic bytes. Delete db.bin (and db.lock if present) to start fresh.",
    };
  }

  const formatVersion = fileContents.readUInt16BE(4);
  const schemaVersion = fileContents.readUInt32BE(6);
  const schemaHashHex = fileContents.subarray(10, 42).toString("hex");
  const wire3Data = fileContents.subarray(DB_HEADER_SIZE);
  return { formatVersion, schemaVersion, schemaHashHex, wire3Data };
}

/**
 * Construct a db.bin buffer.
 * @param {string} schemaHashHex - 64-character hex string
 * @param {number} schemaVersion - Schema version counter
 * @param {Buffer} wire3Data - Wire3-encoded data
 * @returns {Buffer}
 */
export function buildDbBin(schemaHashHex, schemaVersion, wire3Data) {
  const hashBytes = Buffer.from(schemaHashHex, "hex");
  const data = Buffer.isBuffer(wire3Data) ? wire3Data : Buffer.from(wire3Data);
  const buf = Buffer.alloc(DB_HEADER_SIZE + data.length);
  DB_MAGIC.copy(buf, 0);
  buf.writeUInt16BE(DB_FORMAT_VERSION, 4);
  buf.writeUInt32BE(schemaVersion, 6);
  hashBytes.copy(buf, 10);
  data.copy(buf, DB_HEADER_SIZE);
  return buf;
}
