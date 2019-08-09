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

      // <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon-180x180.png">
      // <link rel="apple-touch-icon" sizes="1024x1024" href="/apple-touch-icon-1024x1024.png">
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

  type Head = { name: string; attributes: [string, string][] };

  function appendTag(tagDetails: Head) {
    const meta = document.createElement(tagDetails.name);
    tagDetails.attributes.forEach(([name, value]) => {
      meta.setAttribute(name, value);
    });
    document.getElementsByTagName("head")[0].appendChild(meta);
  }
}
/*
<link rel="apple-touch-icon" sizes="57x57" href="/apple-touch-icon-57x57.png">
<link rel="apple-touch-icon" sizes="60x60" href="/apple-touch-icon-60x60.png">
<link rel="apple-touch-icon" sizes="72x72" href="/apple-touch-icon-72x72.png">
<link rel="apple-touch-icon" sizes="76x76" href="/apple-touch-icon-76x76.png">
<link rel="apple-touch-icon" sizes="114x114" href="/apple-touch-icon-114x114.png">
<link rel="apple-touch-icon" sizes="120x120" href="/apple-touch-icon-120x120.png">
<link rel="apple-touch-icon" sizes="144x144" href="/apple-touch-icon-144x144.png">
<link rel="apple-touch-icon" sizes="152x152" href="/apple-touch-icon-152x152.png">
<link rel="apple-touch-icon" sizes="167x167" href="/apple-touch-icon-167x167.png">
<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon-180x180.png">
<link rel="apple-touch-icon" sizes="1024x1024" href="/apple-touch-icon-1024x1024.png">

*/
