import { defineConfig } from "cypress";

export default defineConfig({
  defaultCommandTimeout: 20000,
  video: false,
  screenshotOnRunFailure: false,
  e2e: {
    setupNodeEvents() {},
    baseUrl: "http://127.0.0.1:8888",
    specPattern: "cypress/e2e/**/*.netlify.cy.js",
  },
});
