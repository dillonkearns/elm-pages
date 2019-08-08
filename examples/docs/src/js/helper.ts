export function pagesInit({ mainElmModule, imageAssets }: any) {
  document.addEventListener("DOMContentLoaded", function() {
    let app = mainElmModule.init({
      flags: { imageAssets }
    });

    app.ports.toJsPort.subscribe((headTags: [Head]) => {
      if (navigator.userAgent.indexOf("Headless") >= 0) {
        headTags.forEach(headTag => {
          appendTag(headTag);
        });
      }
      document.dispatchEvent(new Event("prerender-trigger"));
    });
  });

  type Head = { name: string; attributes: [[string, string]] };

  function appendTag(tagDetails: Head) {
    const meta = document.createElement(tagDetails.name);
    tagDetails.attributes.forEach(([name, value]) => {
      meta.setAttribute(name, value);
    });
    document.getElementsByTagName("head")[0].appendChild(meta);
  }
}
