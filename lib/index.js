module.exports = function pagesInit({ mainElmModule, imageAssets }) {
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
};
