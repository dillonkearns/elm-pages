const path = require("path");

async function resolveConfig() {
  return await import(path.join(process.cwd(), "elm-pages.config.mjs"))
    .then(async (elmPagesConfig) => {
      return (
        elmPagesConfig.default || {
          headTagsTemplate: defaultHeadTagsTemplate,
        }
      );
    })
    .catch((error) => {
      console.warn(
        "No `elm-pages.config.mjs` file found. Using default config."
      );
      return {
        headTagsTemplate: defaultHeadTagsTemplate,
        vite: {},
      };
    });
}

function defaultHeadTagsTemplate(context) {
  return `
<link rel="stylesheet" href="/style.css" />
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<meta name="generator" content="elm-pages v${context.cliVersion}" />
<meta name="mobile-web-app-capable" content="yes" />
<meta name="theme-color" content="#ffffff" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta
  name="apple-mobile-web-app-status-bar-style"
  content="black-translucent"
/>
`;
}

module.exports = { resolveConfig };
