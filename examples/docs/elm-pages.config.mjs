import { defineConfig } from "vite";
import { ViteWebfontDownload } from "vite-plugin-webfont-dl";

export default {
  vite: defineConfig({
    plugins: [
      ViteWebfontDownload([
        "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono&display=swap&subset=latin",
      ]),
    ],
  }),
};
