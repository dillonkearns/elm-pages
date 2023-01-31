import kleur from "kleur";
import crypto from "crypto";
import { PrismaClient } from "@prisma/client";
const prisma = new PrismaClient();

kleur.enabled = true;

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
