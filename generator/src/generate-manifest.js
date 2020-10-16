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
    start_url: config.start_url,
    background_color: config.background_color,
    theme_color: config.theme_color,
    icons: [
      {
        src: "android-chrome-36x36.png",
        sizes: "36x36",
        type: "image/png",
      },
      {
        src: "android-chrome-48x48.png",
        sizes: "48x48",
        type: "image/png",
      },
      {
        src: "android-chrome-72x72.png",
        sizes: "72x72",
        type: "image/png",
      },
      {
        src: "android-chrome-96x96.png",
        sizes: "96x96",
        type: "image/png",
      },
      {
        src: "android-chrome-144x144.png",
        sizes: "144x144",
        type: "image/png",
      },
      {
        src: "android-chrome-192x192.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "android-chrome-256x256.png",
        sizes: "256x256",
        type: "image/png",
      },
      {
        src: "android-chrome-384x384.png",
        sizes: "384x384",
        type: "image/png",
      },
      {
        src: "android-chrome-512x512.png",
        sizes: "512x512",
        type: "image/png",
      },
    ],
  };
}
