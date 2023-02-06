import { PrismaClient } from "@prisma/client";
import { PrismaClientKnownRequestError } from "@prisma/client/runtime/index.js";

const prisma = new PrismaClient();

export async function createPost({ slug, title, body, publish }) {
  try {
    await prisma.post.create({
      data: {
        slug,
        title,
        body,
        publish,
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

export async function updatePost({ slug, title, body, publish }) {
  try {
    const data = {
      slug,
      title,
      body,
      publish: new Date(publish),
    };
    await prisma.post.upsert({
      where: {
        slug,
      },
      create: data,
      update: data,
    });
    return null;
  } catch (e) {
    if (e instanceof PrismaClientKnownRequestError) {
      // https://www.prisma.io/docs/reference/api-reference/error-reference
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

export async function getPost(slug) {
  try {
    return await prisma.post.findFirst({
      where: {
        slug,
      },
      select: {
        body: true,
        title: true,
        slug: true,
        publish: true,
      },
    });
  } catch (e) {
    console.log("ERROR");
    console.trace(e);
    return null;
  }
}

export async function posts() {
  return await prisma.post.findMany({
    orderBy: {
      title: "asc",
    },
  });
}
