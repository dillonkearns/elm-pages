// @ts-ignore
// const { Elm } = require("./src/Main.elm");
import { Elm } from "/main.js";
// const pagesInit = require("../../index.js");

pagesInit({
  mainElmModule: Elm.Main,
});

function pagesInit(config) {
  const path = window.location.pathname.replace(/(\w)$/, "$1/");

  httpGet(`${window.location.origin}${path}content.json`).then(function (
    /** @type {JSON} */ contentJson
  ) {
    const app = config.mainElmModule.init({
      flags: {
        secrets: null,
        baseUrl: document.baseURI,
        isPrerendering: false,
        isDevServer: false,
        isElmDebugMode: false,
        contentJson,
      },
    });
  });
}

function httpGet(/** @type string */ theUrl) {
  return new Promise(function (resolve, reject) {
    const xmlHttp = new XMLHttpRequest();
    xmlHttp.onreadystatechange = function () {
      if (xmlHttp.readyState == 4 && xmlHttp.status == 200)
        resolve(JSON.parse(xmlHttp.responseText));
    };
    xmlHttp.onerror = reject;
    xmlHttp.open("GET", theUrl, true); // true for asynchronous
    xmlHttp.send(null);
  });
}
