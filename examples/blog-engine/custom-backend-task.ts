import { PrismaClient } from "@prisma/client";
import { PrismaClientKnownRequestError } from "@prisma/client/runtime/index.js";

const prisma = new PrismaClient();

export async function createPost({ slug, title, body }) {
  try {
    await prisma.post.create({
      data: {
        slug,
        title,
        body,
      },
    });
  } catch (e) {
    if (e instanceof PrismaClientKnownRequestError) {
      console.log("MESSAGE:", e.message, e.meta, e.code, e.name);
      console.dir(e);

      return { errorMessage: e.message };

      // specific error
    } else {
      console.trace(e);
      throw e;
    }
  }
}

export async function posts() {
  return (await prisma.post.findMany()).map(transformDates);
}

function transformDates(item) {
  return Object.fromEntries(
    Object.entries(item).map(([key, value]) => [key, transformValue(value)])
  );
}

function transformValue(value) {
  //   if (typeof value === "bigint") {
  //     obj[key] = toNumber(value);
  //   }
  if (value instanceof Date) {
    return value.getMilliseconds();
  } else {
    return value;
  }
}
