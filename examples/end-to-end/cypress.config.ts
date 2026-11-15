import { defineConfig } from "cypress";
import { tasks } from "./cypress/tasks.mjs";

export default defineConfig({
  defaultCommandTimeout: 20000,
  e2e: {
    setupNodeEvents(on, config) {
      on("task", tasks);
    },
    baseUrl: "http://localhost:1234",
  },
});
