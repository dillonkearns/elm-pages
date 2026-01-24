import { defineConfig } from "cypress";
export default defineConfig({
    defaultCommandTimeout: 20000,
    e2e: {
        setupNodeEvents(on, config) { },
        baseUrl: "http://localhost:1234",
    },
});
