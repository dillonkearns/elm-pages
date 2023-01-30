import kleur from "kleur";
import crypto from "crypto";
import { PrismaClient } from "@prisma/client";
const prisma = new PrismaClient();

kleur.enabled = true;

export async function users() {
  const users = await prisma.user.findMany();
}

export async function getTodosBySession(sessionId) {
  try {
    return (
      await prisma.session.findUnique({
        where: { id: sessionId },
        include: {
          user: {
            select: {
              todos: {
                select: {
                  complete: true,
                  // , createdAt: true

                  id: true,
                  title: true,
                },
              },
            },
          },
        },
      })
    )?.user.todos;
  } catch (e) {
    console.trace(e);
    return null;
  }
}

export async function getEmailBySessionId(sessionId: string) {
  try {
    return (
      await prisma.session.findUnique({
        where: { id: sessionId },
        include: {
          user: {
            select: { email: true },
          },
        },
      })
    )?.user.email;
  } catch (e) {
    console.trace(e);
    return null;
  }
}

export async function findOrCreateUserAndSession({
  confirmedEmail,
  expirationTime,
}) {
  try {
    const expirationDate = new Date(expirationTime);
    const result = await prisma.user.upsert({
      where: { email: confirmedEmail },
      create: {
        email: confirmedEmail,
        sessions: { create: { expirationDate } },
      },
      update: { sessions: { create: { expirationDate } } },
      // TODO should this be descending? Or is `asc` correct?
      include: { sessions: { take: 1, orderBy: { createdAt: "asc" } } },
    });
    return result.sessions[0].id;
  } catch (e) {
    console.trace(e);
    return null;
  }
}

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
