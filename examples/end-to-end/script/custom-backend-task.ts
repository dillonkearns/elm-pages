import { Transform } from "node:stream";

export async function hello(input, { cwd, env }) {
  return `Hello!`;
}

export async function upperCaseStream() {
  return new Transform({
    transform(chunk, encoding, callback) {
      callback(null, chunk.toString().toUpperCase());
    },
  });
}

export async function readStreamNotADuplex() {
  return process.stdin;
}
