import { defineConfig } from "cypress";

// Tests that run against a production build (`elm-pages build`), served by
// `node serve-dist.mjs`. The other Cypress tests run against the dev server.
export default defineConfig({
  defaultCommandTimeout: 20000,
  e2e: {
    setupNodeEvents(on, config) {},
    baseUrl: "http://localhost:3457",
    specPattern: "cypress/production/**/*.cy.js",
  },
});
