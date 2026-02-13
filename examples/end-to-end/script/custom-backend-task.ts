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

/**
 * Build a multipart body from structured parts using FormData (same approach
 * as request-cache.js), then parse it with busboy to verify the round-trip.
 */
export async function buildAndParseMultipart(
  parts: Array<{ type: string; name: string; value?: string; mimeType?: string; filename?: string; content?: string }>
) {
  const { default: Busboy } = await import("busboy");
  const formData = partsToFormData(parts);
  const req = new Request("http://localhost", { method: "POST", body: formData });
  const contentType = req.headers.get("content-type")!;
  const body = Buffer.from(await req.arrayBuffer());

  return new Promise((resolve, reject) => {
    const fields: Record<string, string> = {};
    const files: Record<string, { filename: string; mimeType: string; content: string }> = {};

    const busboy = Busboy({
      headers: { "content-type": contentType },
    });

    busboy.on("field", (name: string, value: string) => {
      fields[name] = value;
    });

    busboy.on("file", (name: string, stream: Readable, info: { filename: string; mimeType: string }) => {
      let data = Buffer.alloc(0);
      stream.on("data", (chunk: Buffer) => {
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
    readable.push(body);
    readable.push(null);
    readable.pipe(busboy);
  });
}

/**
 * Build a multipart body from structured parts using FormData, then check
 * whether the raw bytes contain a specific string (for header injection tests).
 */
export async function buildAndCheckRawBytes({ parts, searchFor }: { parts: Array<any>; searchFor: string }) {
  const formData = partsToFormData(parts);
  const req = new Request("http://localhost", { method: "POST", body: formData });
  const body = Buffer.from(await req.arrayBuffer());
  return body.toString("utf-8").includes(searchFor);
}

function partsToFormData(
  parts: Array<{ type: string; name: string; value?: string; mimeType?: string; filename?: string; content?: string }>
): FormData {
  const formData = new FormData();
  for (const part of parts) {
    switch (part.type) {
      case "string":
        formData.append(part.name, part.value!);
        break;
      case "bytes":
        formData.append(
          part.name,
          new Blob([Buffer.from(part.content!, "base64")], { type: part.mimeType })
        );
        break;
      case "bytesWithFilename":
        formData.append(
          part.name,
          new Blob([Buffer.from(part.content!, "base64")], { type: part.mimeType }),
          part.filename
        );
        break;
    }
  }
  return formData;
}

function stdout() {
  return new Writable({
    write(chunk, encoding, callback) {
      process.stdout.write(chunk, callback);
    },
  });
}
