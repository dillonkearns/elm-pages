import kleur from "kleur";
kleur.enabled = true;
export async function log(message) {
    console.log(message);
    return null;
}
export async function logReturn(message) {
    console.log(message);
    return message.length;
}
