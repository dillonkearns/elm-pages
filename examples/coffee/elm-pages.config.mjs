import { defineConfig } from "vite";
import adapter from "../../adapter/netlify.js";

export default {
  vite: defineConfig({}),
  adapter,

  // Inject the Google Fonts <link> tags directly so the browser preconnects
  // and discovers the font files during HTML parse, instead of waiting for
  // CSS @import resolution. Matches the design's intended typography:
  //   serif: Instrument Serif
  //   sans:  Geist
  //   mono:  Geist Mono
  headTagsTemplate(context) {
    return `
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Geist:wght@300;400;500;600;700&family=Geist+Mono:wght@400;500&display=swap" />
<link rel="stylesheet" href="/style.css" />
<meta name="generator" content="elm-pages v${context.cliVersion}" />
`;
  },
};
