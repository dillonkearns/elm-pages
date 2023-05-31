import * as path from "path";

export async function resolveConfig() {
  const initialConfig = await await import(
    path.join(process.cwd(), "elm-pages.config.mjs")
  )
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

  return {
    preloadTagForFile: function () {
      return true;
    },
    headTagsTemplate: defaultHeadTagsTemplate,
    vite: {},
    ...initialConfig,
  };
}

function defaultHeadTagsTemplate(context) {
  return `
<link rel="stylesheet" href="/style.css" />
<meta name="generator" content="elm-pages v${context.cliVersion}" />
`;
}
