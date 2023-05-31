import { PrismaClient } from "@prisma/client";
const prisma = new PrismaClient();

[...Array(9).keys()].forEach(async (index) => {
  let slug = `${index + 1}`;
  const post = { title: slug, body: slug, slug };
  await prisma.post.upsert({
    where: { slug },
    update: post,
    create: post,
  });
});

// posts.forEach(async (post) => {
//   await prisma.post.upsert({
//     where: { slug: post.slug },
//     update: post,
//     create: post,
//   });
// });
