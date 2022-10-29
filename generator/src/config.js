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
<meta name="generator" content="elm-pages v${context.cliVersion}" />
`;
}

module.exports = { resolveConfig };
