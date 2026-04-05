import { defineConfig } from "vite";

import adapter from "../../adapter/netlify.js";

export default {
  vite: defineConfig({}),
  adapter,
};
