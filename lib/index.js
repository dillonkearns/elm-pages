const fs = require("fs");
const favicons = require("favicons");

module.exports = {
  pagesInit,
  generateManifest
};

function pagesInit({ mainElmModule, imageAssets }) {
  document.addEventListener("DOMContentLoaded", function() {
    let app = mainElmModule.init({
      flags: { imageAssets }
    });

    app.ports.toJsPort.subscribe(headTags => {
      if (navigator.userAgent.indexOf("Headless") >= 0) {
        headTags.forEach(headTag => {
          appendTag(headTag);
        });
      }

      appendTag({
        name: "link",
        attributes: [
          ["rel", "apple-touch-icon"],
          ["sizes", "180x180"],
          ["href", "/apple-touch-icon-180x180.png"]
        ]
      });
      appendTag({
        name: "link",
        attributes: [
          ["rel", "apple-touch-icon"],
          ["sizes", "1024x1024"],
          ["href", "/apple-touch-icon-1024x1024.png"]
        ]
      });

      appendTag({
        name: "link",
        attributes: [["rel", "manifest"], ["href", "/manifest.webmanifest"]]
      });

      document.dispatchEvent(new Event("prerender-trigger"));
    });
  });

  function appendTag(tagDetails) {
    const meta = document.createElement(tagDetails.name);
    tagDetails.attributes.forEach(([name, value]) => {
      meta.setAttribute(name, value);
    });
    document.getElementsByTagName("head")[0].appendChild(meta);
  }
}

function generateManifest(elmApp) {
  const app = elmApp.init({ flags: null });
  app.ports.generateManifest.subscribe(({ sourceIcon, manifestJson }) => {
    generateIcons(sourceIcon, manifestIcons => {
      manifestJson.icons = manifestIcons;
      fs.writeFileSync(
        "./dist/manifest.webmanifest",
        JSON.stringify(manifestJson)
      );
    });
  });
}

function generateIcons(sourceIcon, topCallback) {
  const configuration = {
    path: "/", // Path for overriding default icons path. `string`
    appName: null, // Your application's name. `string`
    appShortName: null, // Your application's short_name. `string`. Optional. If not set, appName will be used
    appDescription: null, // Your application's description. `string`
    developerName: null, // Your (or your developer's) name. `string`
    developerURL: null, // Your (or your developer's) URL. `string`
    dir: "auto", // Primary text direction for name, short_name, and description
    lang: "en-US", // Primary language for name and short_name
    background: "#fff", // Background colour for flattened icons. `string`
    theme_color: "#fff", // Theme color user for example in Android's task switcher. `string`
    appleStatusBarStyle: "black-translucent", // Style for Apple status bar: "black-translucent", "default", "black". `string`
    display: "standalone", // Preferred display mode: "fullscreen", "standalone", "minimal-ui" or "browser". `string`
    orientation: "any", // Default orientation: "any", "natural", "portrait" or "landscape". `string`
    scope: "/", // set of URLs that the browser considers within your app
    start_url: "/?homescreen=1", // Start URL when launching the application from a device. `string`
    version: "1.0", // Your application's version string. `string`
    logging: false, // Print logs to console? `boolean`
    pixel_art: false, // Keeps pixels "sharp" when scaling up, for pixel art.  Only supported in offline mode.
    loadManifestWithCredentials: false, // Browsers don't send cookies when fetching a manifest, enable this to fix that. `boolean`
    icons: {
      // Platform Options:
      // - offset - offset in percentage
      // - background:
      //   * false - use default
      //   * true - force use default, e.g. set background for Android icons
      //   * color - set background for the specified icons
      //   * mask - apply mask in order to create circle icon (applied by default for firefox). `boolean`
      //   * overlayGlow - apply glow effect after mask has been applied (applied by default for firefox). `boolean`
      //   * overlayShadow - apply drop shadow after mask has been applied .`boolean`
      //
      android: true, // Create Android homescreen icon. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
      appleIcon: true, // Create Apple touch icons. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
      appleStartup: false, // Create Apple startup images. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
      coast: false, // Create Opera Coast icon. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
      favicons: true, // Create regular favicons. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
      firefox: false, // Create Firefox OS icons. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
      windows: false, // Create Windows 8 tile icons. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
      yandex: false // Create Yandex browser icon. `boolean` or `{ offset, background, mask, overlayGlow, overlayShadow }`
    }
  };
  function writeToDist({ name, contents }) {
    fs.writeFileSync(`dist/${name}`, contents);
  }
  const callback = function(error, response) {
    if (error) {
      console.log(error.message);
      return null;
    } else {
      response.images.forEach(writeToDist);
      // console.log(response.html.join("\n"));
      topCallback(JSON.parse(response.files[0].contents).icons);
    }
  };

  favicons(sourceIcon, configuration, callback);
}
