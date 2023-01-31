import crypto from "crypto";
import { PrismaClient } from "@prisma/client";
const prisma = new PrismaClient();

export async function checkAllTodos({ sessionId, toggleTo }) {
  await prisma.todo.updateMany({
    where: {
      userId: await userIdFromSessionId(sessionId),
    },
    data: {
      complete: toggleTo,
    },
  });
}

export async function clearCompletedTodos({ sessionId }) {
  await prisma.todo.deleteMany({
    where: {
      userId: await userIdFromSessionId(sessionId),
      complete: true,
    },
  });
}

async function userIdFromSessionId(sessionId) {
  return (
    await prisma.session.findUniqueOrThrow({
      where: {
        id: sessionId,
      },
      include: {
        user: {
          select: { id: true },
        },
      },
    })
  ).userId;
}

function whereSession(sessionId: string) {
  return {
    sessions: {
      some: {
        id: sessionId,
      },
    },
  };
}

export async function updateTodo({ sessionId, todoId, description }) {
  await prisma.todo.updateMany({
    where: {
      user: whereSession(sessionId),
      id: todoId,
    },
    data: {
      title: description,
    },
  });
}

export async function deleteTodo({ sessionId, todoId }) {
  await prisma.todo.deleteMany({
    where: {
      id: todoId,
      user: whereSession(sessionId),
    },
  });
}

export async function setTodoCompletion({ sessionId, todoId, complete }) {
  await prisma.todo.updateMany({
    where: {
      id: todoId,
      user: whereSession(sessionId),
    },
    data: {
      complete,
    },
  });
}

export async function createTodo({ sessionId, requestTime, description }) {
  try {
    const user = await prisma.session.findUnique({
      where: {
        id: sessionId,
      },
      include: {
        user: {
          select: { id: true },
        },
      },
    });
    await prisma.todo.create({
      data: {
        complete: false,
        title: description,
        user: {
          connect: {
            id: user?.user.id,
          },
        },
        createdAt: new Date(requestTime),
      },
    });
    return null;
  } catch (e) {
    console.trace(e);
    return null;
  }
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
                orderBy: {
                  createdAt: "asc",
                },
                select: {
                  complete: true,
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
      include: {
        sessions: { take: 1, orderBy: { createdAt: "desc" } },
      },
    });
    return result.sessions[0].id;
  } catch (e) {
    console.trace(e);
    return null;
  }
}

/* Encrypt/decrypt code source: https://github.com/kentcdodds/kentcdodds.com/blob/fe107c6d284012a72cc98f076479bfd6dbe7fb02/app/utils/encryption.server.ts */

const algorithm = "aes-256-gcm";

let secret = "not-at-all-secret";
if (process.env.MAGIC_LINK_SECRET) {
  secret = process.env.MAGIC_LINK_SECRET;
} else if (process.env.NODE_ENV === "production") {
  throw new Error("Must set MAGIC_LINK_SECRET");
}

const ENCRYPTION_KEY = crypto.scryptSync(secret, "salt", 32);
const IV_LENGTH = 12;
const UTF8 = "utf8";
const HEX = "hex";

export function encrypt(text: string) {
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(algorithm, ENCRYPTION_KEY, iv);
  let encrypted = cipher.update(text, UTF8, HEX);
  encrypted += cipher.final(HEX);
  const authTag = cipher.getAuthTag();
  return `${iv.toString(HEX)}:${authTag.toString(HEX)}:${encrypted}`;
}

export function decrypt(text: string) {
  const [ivPart, authTagPart, encryptedText] = text.split(":");
  if (!ivPart || !authTagPart || !encryptedText) {
    throw new Error("Invalid text.");
  }

  const iv = Buffer.from(ivPart, HEX);
  const authTag = Buffer.from(authTagPart, HEX);
  const decipher = crypto.createDecipheriv(algorithm, ENCRYPTION_KEY, iv);
  decipher.setAuthTag(authTag);
  let decrypted = decipher.update(encryptedText, HEX, UTF8);
  decrypted += decipher.final(UTF8);
  return decrypted;
}
