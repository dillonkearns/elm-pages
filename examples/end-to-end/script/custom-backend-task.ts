import { Writable, Transform, Readable } from "node:stream";

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
    stream: stdout(),
    metadata: () => {
      return "Hi! I'm metadata from customWriteStream!";
    },
  };
}

export async function parseMultipart({ base64, contentType }) {
  const { default: Busboy } = await import("busboy");
  const buffer = Buffer.from(base64, "base64");

  return new Promise((resolve, reject) => {
    const fields: Record<string, string> = {};
    const files: Record<string, { filename: string; mimeType: string; content: string }> = {};

    const busboy = Busboy({
      headers: { "content-type": contentType },
    });

    busboy.on("field", (name, value) => {
      fields[name] = value;
    });

    busboy.on("file", (name, stream, info) => {
      let data = Buffer.alloc(0);
      stream.on("data", (chunk) => {
        data = Buffer.concat([data, chunk]);
      });
      stream.on("end", () => {
        files[name] = {
          filename: info.filename,
          mimeType: info.mimeType,
          content: data.toString("utf-8"),
        };
      });
    });

    busboy.on("finish", () => {
      resolve({ fields, files });
    });

    busboy.on("error", reject);

    const readable = new Readable();
    readable.push(buffer);
    readable.push(null);
    readable.pipe(busboy);
  });
}

export async function rawBytesContain({ base64, searchFor }) {
  const buffer = Buffer.from(base64, "base64");
  const text = buffer.toString("utf-8");
  return text.includes(searchFor);
}

function stdout() {
  return new Writable({
    write(chunk, encoding, callback) {
      process.stdout.write(chunk, callback);
    },
  });
}
