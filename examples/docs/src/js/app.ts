// @ts-ignore
import { Elm } from "../Main.elm";
// @ts-ignore
import { imageAssets, routes } from "./image-assets";

document.addEventListener("DOMContentLoaded", function() {
  let app = Elm.Main.init({
    node: document.getElementById("app"),
    flags: { imageAssets, routes }
  });

  app.ports.toJsPort.subscribe((headTags: [headTag]) => {
    if (navigator.userAgent.indexOf("Headless") >= 0) {
      headTags.forEach(headTag => {
        appendTag(headTag);
      });
    }
    document.dispatchEvent(new Event("prerender-trigger"));
  });
});

type headTag = { name: string; attributes: [[string, string]] };

function appendTag(tagDetails: headTag) {
  const meta = document.createElement(tagDetails.name);
  tagDetails.attributes.forEach(([name, value]) => {
    meta.setAttribute(name, value);
  });
  document.getElementsByTagName("head")[0].appendChild(meta);
}
