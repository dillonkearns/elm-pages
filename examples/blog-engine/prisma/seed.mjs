import { PrismaClient } from "@prisma/client";
const prisma = new PrismaClient();

const posts = [
  {
    slug: "elm-pages demo",
    title: "Is elm-pages Full-Stack?",
    body: `
# Is elm-pages Full-Stack?

Yes it is!
    `.trim(),
  },
];

posts.forEach(async (post) => {
  await prisma.post.upsert({
    where: { slug: post.slug },
    update: post,
    create: post,
  });
});
