import kleur from "kleur";

kleur.enabled = true;

export async function log(message: string) {
  console.log(message);
  return null;
}

export async function logReturn(message: string) {
  console.log(message);
  return message.length;
}
