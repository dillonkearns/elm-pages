import { Transform, Readable } from "node:stream";

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

export async function customReadStream() {
  return new Readable({
    read(size) {
      this.push("hello");
      this.push(null);
    },
  });
}
