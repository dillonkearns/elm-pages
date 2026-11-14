import { defineConfig } from "cypress";

// Tests that run against plain `elm-pages dev` (no `--debug`), on its own port
// so it does not clash with the `--debug` dev server the other tests use.
export default defineConfig({
  defaultCommandTimeout: 20000,
  e2e: {
    setupNodeEvents(on, config) {},
    baseUrl: "http://localhost:1235",
    specPattern: "cypress/dev-default/**/*.cy.js",
  },
});
