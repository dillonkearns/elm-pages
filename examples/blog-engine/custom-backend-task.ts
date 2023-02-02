import kleur from "kleur";
import fs from "node:fs";
import path from "node:path";

kleur.enabled = true;

export async function environmentVariable(name: string) {
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

export async function hello(name: string) {
  await waitFor(1000);
  return `147 ${name}!!`;
}

function waitFor(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function addItem(name: string) {
  let timeToWait = 0;
  try {
    timeToWait = parseInt(name);
  } catch (e) {}

  console.log("Adding ", name);
  await fs.promises.writeFile(path.join(folder, name), "");
  await waitFor(timeToWait);
  return await listFiles();
}
const folder = "./items-list";

async function listFiles(): Promise<string[]> {
  return (await fs.promises.readdir(folder)).filter(
    (file) => !file.startsWith(".")
  );
}

export async function getItems() {
  return await listFiles();
}

export async function deleteAllItems(name: string) {
  for (const file of await listFiles()) {
    await fs.promises.unlink(path.join(folder, file));
  }

  return await listFiles();
}

export async function log(message: string) {
  console.log(message);
  return null;
}
