import kleur from "kleur";
kleur.enabled = true;

global.list = ["Initial Item"];

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
  await waitFor(1000);
  return `147 ${name}!!`;
}

function waitFor(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function addItem(name) {
  global.list.push(name);
  return global.list;
}

export async function getItems() {
  return global.list;
}

export async function deleteAllItems(name) {
  global.list = [];
  return global.list;
}
