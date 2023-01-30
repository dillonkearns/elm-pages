import kleur from "kleur";
import something from "./something.ts";
import { PrismaClient } from "@prisma/client";
const prisma = new PrismaClient();

export async function users() {
  try {
    return await prisma.user.findMany();
  } catch (error) {
    console.trace(error);
    return ["PRISMA ERROR"];
  }
}

export async function environmentVariable(name) {
  const result = process.env[name];
  if (result) {
    return result;
  } else {
    throw `No environment variable called ${kleur
      .yellow()
      .underline(name)}\n\nAvailable:\n\n${Object.keys(process.env)
      .slice(0, 5)
      .join("\n")}`;
  }
}

export async function hello(name) {
  return `${something} 149 ${name}!!`;
}

function waitFor(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
