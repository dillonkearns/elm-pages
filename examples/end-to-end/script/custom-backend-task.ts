import { Transform, Readable } from "node:stream";

export async function hello(input, { cwd, env }) {
  return `Hello!`;
}

export async function upperCaseStream() {
  return {
    metadata: () => "Hi! I'm metadata from upperCaseStream!",
    stream: new Transform({
      transform(chunk, encoding, callback) {
        callback(null, chunk.toString().toUpperCase());
      },
    }),
  };
}

export async function customReadStream() {
  return new Readable({
    read(size) {
      this.push("Hello from customReadStream!");
      this.push(null);
    },
  });
}

export async function customWrite(input) {
  return {
    stream: process.stdout,
    metadata: () => {
      return "Hi! I'm metadata from customWriteStream!";
    },
  };
}
