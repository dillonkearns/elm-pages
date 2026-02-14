"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkAllTodos = checkAllTodos;
exports.clearCompletedTodos = clearCompletedTodos;
exports.updateTodo = updateTodo;
exports.deleteTodo = deleteTodo;
exports.setTodoCompletion = setTodoCompletion;
exports.createTodo = createTodo;
exports.getTodosBySession = getTodosBySession;
exports.getEmailBySessionId = getEmailBySessionId;
exports.findOrCreateUserAndSession = findOrCreateUserAndSession;
exports.encrypt = encrypt;
exports.decrypt = decrypt;
const crypto_1 = __importDefault(require("crypto"));
const client_1 = require("@prisma/client");
const prisma = new client_1.PrismaClient();
async function checkAllTodos({ sessionId, toggleTo }) {
    await prisma.todo.updateMany({
        where: {
            userId: await userIdFromSessionId(sessionId),
        },
        data: {
            complete: toggleTo,
        },
    });
}
async function clearCompletedTodos({ sessionId }) {
    await prisma.todo.deleteMany({
        where: {
            userId: await userIdFromSessionId(sessionId),
            complete: true,
        },
    });
}
async function userIdFromSessionId(sessionId) {
    return (await prisma.session.findUniqueOrThrow({
        where: {
            id: sessionId,
        },
        include: {
            user: {
                select: { id: true },
            },
        },
    })).userId;
}
function whereSession(sessionId) {
    return {
        sessions: {
            some: {
                id: sessionId,
            },
        },
    };
}
async function updateTodo({ sessionId, todoId, description }) {
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
async function deleteTodo({ sessionId, todoId }) {
    await prisma.todo.deleteMany({
        where: {
            id: todoId,
            user: whereSession(sessionId),
        },
    });
}
async function setTodoCompletion({ sessionId, todoId, complete }) {
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
async function createTodo({ sessionId, requestTime, description }) {
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
    }
    catch (e) {
        console.trace(e);
        return null;
    }
}
async function getTodosBySession(sessionId) {
    try {
        return (await prisma.session.findUnique({
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
        }))?.user.todos;
    }
    catch (e) {
        console.trace(e);
        return null;
    }
}
async function getEmailBySessionId(sessionId) {
    try {
        return (await prisma.session.findUnique({
            where: { id: sessionId },
            include: {
                user: {
                    select: { email: true },
                },
            },
        }))?.user.email;
    }
    catch (e) {
        console.trace(e);
        return null;
    }
}
async function findOrCreateUserAndSession({ confirmedEmail, expirationTime, }) {
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
    }
    catch (e) {
        console.trace(e);
        return null;
    }
}
/* Encrypt/decrypt code source: https://github.com/kentcdodds/kentcdodds.com/blob/fe107c6d284012a72cc98f076479bfd6dbe7fb02/app/utils/encryption.server.ts */
const algorithm = "aes-256-gcm";
let secret = "not-at-all-secret";
if (process.env.MAGIC_LINK_SECRET) {
    secret = process.env.MAGIC_LINK_SECRET;
}
else if (process.env.NODE_ENV === "production") {
    throw new Error("Must set MAGIC_LINK_SECRET");
}
const ENCRYPTION_KEY = crypto_1.default.scryptSync(secret, "salt", 32);
const IV_LENGTH = 12;
const UTF8 = "utf8";
const HEX = "hex";
function encrypt(text) {
    const iv = crypto_1.default.randomBytes(IV_LENGTH);
    const cipher = crypto_1.default.createCipheriv(algorithm, ENCRYPTION_KEY, iv);
    let encrypted = cipher.update(text, UTF8, HEX);
    encrypted += cipher.final(HEX);
    const authTag = cipher.getAuthTag();
    return `${iv.toString(HEX)}:${authTag.toString(HEX)}:${encrypted}`;
}
function decrypt(text) {
    const [ivPart, authTagPart, encryptedText] = text.split(":");
    if (!ivPart || !authTagPart || !encryptedText) {
        throw new Error("Invalid text.");
    }
    const iv = Buffer.from(ivPart, HEX);
    const authTag = Buffer.from(authTagPart, HEX);
    const decipher = crypto_1.default.createDecipheriv(algorithm, ENCRYPTION_KEY, iv);
    decipher.setAuthTag(authTag);
    let decrypted = decipher.update(encryptedText, HEX, UTF8);
    decrypted += decipher.final(UTF8);
    return decrypted;
}
