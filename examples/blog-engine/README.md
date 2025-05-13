# Blog Engine

## To run locally

1. Run `npm i` and then `npm run build:generator` in `elm-pages` root if you have not already.
2. Run `npm i` and then `npm run build` in this project directory.
3. This project requires a database and uses `prisma` to interact with it.

   1. Have a Postgres database running. One way to do this is to have docker installed and run these command:
      ```bash
      docker pull postgres
      ```
      to download a docker image of postgres and then
      ```bash
      docker run -d --name postgres-container -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres
      ```
      to run a container with the image. This will start a postgres database on `localhost:5432` with the username `postgres` and password `postgres`.
   2. Set the environment variable `BLOG_DATABASE_URL` to the connection string of the database e.g.
      ```bash
      export BLOG_DATABASE_URL=postgresql://postgres:postgres@localhost/postgres
      ```
   3. To set up the database tables configured in `prisma/schema.prisma`, run

      ```bash
      npx prisma migrate dev --name init
      ```

   4. To generate som example blog posts you can run
      ```bash
      node prisma/seed.js
      ```

4. Start elm-pages dev with
   ```bash
   npm run start
   ```
