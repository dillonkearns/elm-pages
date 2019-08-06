export function pagesInit({ mainElmModule, imageAssets }: any) {
  document.addEventListener("DOMContentLoaded", function() {
    let app = mainElmModule.init({
      node: document.getElementById("app"),
      flags: { imageAssets }
    });

    app.ports.toJsPort.subscribe((Heads: [Head]) => {
      if (navigator.userAgent.indexOf("Headless") >= 0) {
        Heads.forEach(Head => {
          appendTag(Head);
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
