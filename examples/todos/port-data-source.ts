import kleur from "kleur";
import crypto from "crypto";

kleur.enabled = true;

/* Encrypt/decrypt code source: https://github.com/kentcdodds/kentcdodds.com/blob/43130b0d9033219920a46bb8a4f009781afa02f1/app/utils/encryption.server.ts */

const algorithm = "aes-256-ctr";

let secret = "not-at-all-secret";
if (process.env.MAGIC_LINK_SECRET) {
  secret = process.env.MAGIC_LINK_SECRET;
} else if (process.env.NODE_ENV === "production") {
  throw new Error("Must set MAGIC_LINK_SECRET");
}

const ENCRYPTION_KEY = crypto.scryptSync(secret, "salt", 32);

const IV_LENGTH = 16;

export function encrypt(text: string) {
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(algorithm, ENCRYPTION_KEY, iv);
  const encrypted = Buffer.concat([cipher.update(text), cipher.final()]);
  return `${iv.toString("hex")}:${encrypted.toString("hex")}`;
}

export function decrypt(text: string) {
  const [ivPart, encryptedPart] = text.split(":");
  if (!ivPart || !encryptedPart) {
    throw new Error("Invalid text.");
  }

  const iv = Buffer.from(ivPart, "hex");
  const encryptedText = Buffer.from(encryptedPart, "hex");
  const decipher = crypto.createDecipheriv(algorithm, ENCRYPTION_KEY, iv);
  const decrypted = Buffer.concat([
    decipher.update(encryptedText),
    decipher.final(),
  ]);
  return decrypted.toString();
}

export function now() {
  return Date.now();
}

export function log(message) {
  console.log(message);
  return null;
}
