const seo = require("./seo-renderer.js");

/** @typedef { { head: any[]; errors: any[]; contentJson: any[]; html: string; route: string; title: string; } } Arg */
/** @typedef { { tag : 'PageProgress'; args : Arg[] } } PageProgress */

module.exports = function wrapHtml(
  basePath,
  fromElm,
  contentJson,
  devServer,
  contentDatPayload
) {
  const devServerOnly = (/** @type {string} */ devServerOnlyString) =>
    devServer ? devServerOnlyString : "";
  const seoData = seo.gather(fromElm.head);
  return {
    kind: "html-template",
    title: fromElm.title,
    html: fromElm.html,
    bytesData: Buffer.from(contentDatPayload.buffer).toString("base64"),
    headTags: seoData.headTags,
    rootElement: seoData.rootElement,
  };
};

function devServerStyleTag() {
  /*html*/
  return `<style>
@keyframes lds-default {
    0%, 20%, 80%, 100% {
      transform: scale(1);
    }
    50% {
      transform: scale(1.5);
    }
  }

#not-found-reason code {
  color: rgb(226, 0, 124);
}

#not-found-reason h1 {
  font-size: 26px;
  font-weight: bold;
  padding-bottom: 15px;
}

#not-found-reason a:hover {
  text-decoration: underline;
}
</style>`;
}
