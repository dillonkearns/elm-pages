"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.users = users;
exports.environmentVariable = environmentVariable;
exports.hello = hello;
const kleur_1 = __importDefault(require("kleur"));
const something_ts_1 = __importDefault(require("./something.ts"));
const client_1 = require("@prisma/client");
const prisma = new client_1.PrismaClient();
async function users() {
    try {
        return await prisma.user.findMany();
    }
    catch (error) {
        console.trace(error);
        return ["PRISMA ERROR"];
    }
}
async function environmentVariable(name) {
    const result = process.env[name];
    if (result) {
        return result;
    }
    else {
        throw `No environment variable called ${kleur_1.default
            .yellow()
            .underline(name)}\n\nAvailable:\n\n${Object.keys(process.env)
            .slice(0, 5)
            .join("\n")}`;
    }
}
async function hello(name) {
    return `${something_ts_1.default} 149 ${name}!!`;
}
function waitFor(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
