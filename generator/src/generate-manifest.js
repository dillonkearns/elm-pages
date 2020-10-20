/**
 * @param {{ name: string; short_name: string; description: string; display: string; orientation: string; serviceworker: { scope: string; }; start_url: string; background_color: string; theme_color: string; }} config
 */
function generate(config) {
  return {
    name: config.name,
    short_name: config.short_name,
    description: config.description,
    dir: "auto",
    lang: "en-US",
    display: config.display,
    orientation: config.orientation,
    scope: config.serviceworker.scope,
    start_url: `/${config.start_url}`,
    background_color: config.background_color,
    theme_color: config.theme_color,
    icons: config.icons,
  };
}

module.exports = generate;
