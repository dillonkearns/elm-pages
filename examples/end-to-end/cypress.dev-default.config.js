import { defineConfig } from "cypress";
import { tasks } from "./cypress/tasks.mjs";

// Tests that run against plain `elm-pages dev` (no `--debug`), on its own port
// so it does not clash with the `--debug` dev server the other tests use.
export default defineConfig({
  defaultCommandTimeout: 20000,
  e2e: {
    setupNodeEvents(on, config) {
      on("task", tasks);
    },
    baseUrl: "http://localhost:1235",
    specPattern: [
      "cypress/dev-default/**/*.cy.js",
      // Hot reloading (of code and of data) and the first render must work in both modes, so these
      // specs run here too.
      "cypress/e2e/hot-reload.cy.js",
      "cypress/e2e/hot-data-reload.cy.js",
      "cypress/e2e/first-render.cy.js",
    ],
  },
});
