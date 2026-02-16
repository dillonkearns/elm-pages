import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";
import { ViteWebfontDownload } from "vite-plugin-webfont-dl";
import adapter from "../../adapter/netlify.js";

export default {
  vite: defineConfig({
    plugins: [
      tailwindcss(),
      ViteWebfontDownload([
        "https://fonts.googleapis.com/css2?family=IBM+Plex+Mono&display=swap&subset=latin",
      ]),
    ],
  }),
  adapter,
  headTagsTemplate(context) {
    return `
<link rel="stylesheet" href="/style.css" />
<meta name="generator" content="elm-pages v${context.cliVersion}" />
`;
  },
  preloadTagForFile(file) {
    return !file.endsWith(".css");
  },
};
