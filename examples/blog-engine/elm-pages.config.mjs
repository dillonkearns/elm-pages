import { defineConfig } from "vite";
import adapter from "./adapter.mjs";

export default {
  vite: defineConfig({}),
  adapter,
};
