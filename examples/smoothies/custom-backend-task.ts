import kleur from "kleur";
import bcrypt from "bcryptjs";

kleur.enabled = true;

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
  return `147 ${name}!!`;
}
export async function hashPassword(password) {
  return await bcrypt.hash(password, process.env.SMOOTHIES_SALT);
}

function waitFor(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
