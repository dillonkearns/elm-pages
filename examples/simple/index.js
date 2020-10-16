// @ts-ignore
// const { Elm } = require("./src/Main.elm");
import { Elm } from "/main.js";
import userInit from "/user-index.js";
// const pagesInit = require("../../index.js");

let prefetchedPages;
let initialLocationHash;
let elmViewRendered = false;

function pagesInit(
  /** @type { mainElmModule: { init: any  } } */ { mainElmModule }
) {
  prefetchedPages = [window.location.pathname];
  initialLocationHash = document.location.hash.replace(/^#/, "");

  return new Promise(function (resolve, reject) {
    document.addEventListener("DOMContentLoaded", (_) => {
      new MutationObserver(function () {
        elmViewRendered = true;
      }).observe(document.body, {
        attributes: true,
        childList: true,
        subtree: true,
      });

      loadContentAndInitializeApp(mainElmModule).then(resolve, reject);
    });
  });
}

function loadContentAndInitializeApp(
  /** @type { init: any  } */ mainElmModule
) {
  const path = window.location.pathname.replace(/(\w)$/, "$1/");

  return Promise.all([
    httpGet(`${window.location.origin}${path}content.json`),
  ]).then(function (/** @type {[JSON]} */ [contentJson]) {
    const app = mainElmModule.init({
      flags: {
        secrets: null,
        baseUrl: document.baseURI,
        isPrerendering: false,
        isDevServer: false,
        isElmDebugMode: false,
        contentJson,
      },
    });

    app.ports.toJsPort.subscribe((
      /** @type { { allRoutes: string[] } }  */ fromElm
    ) => {
      window.allRoutes = fromElm.allRoutes.map(
        (route) => new URL(route, document.baseURI).href
      );

      setupLinkPrefetching();
    });

    return app;
  });
}

function setupLinkPrefetching() {
  new MutationObserver(observeFirstRender).observe(document.body, {
    attributes: true,
    childList: true,
    subtree: true,
  });
}

function loadNamedAnchor() {
  if (initialLocationHash !== "") {
    const namedAnchor = document.querySelector(`[name=${initialLocationHash}]`);
    namedAnchor && namedAnchor.scrollIntoView();
  }
}

function observeFirstRender(
  /** @type {MutationRecord[]} */ mutationList,
  /** @type {MutationObserver} */ firstRenderObserver
) {
  loadNamedAnchor();
  for (let mutation of mutationList) {
    if (mutation.type === "childList") {
      setupLinkPrefetchingHelp();
    }
  }
  firstRenderObserver.disconnect();
  new MutationObserver(observeUrlChanges).observe(document.body.children[0], {
    attributes: true,
    childList: false,
    subtree: false,
  });
}

function observeUrlChanges(
  /** @type {MutationRecord[]} */ mutationList,
  /** @type {MutationObserver} */ _theObserver
) {
  for (let mutation of mutationList) {
    if (
      mutation.type === "attributes" &&
      mutation.attributeName === "data-url"
    ) {
      setupLinkPrefetchingHelp();
    }
  }
}

function setupLinkPrefetchingHelp(
  /** @type {MutationObserver} */ _mutationList,
  /** @type {MutationObserver} */ _theObserver
) {
  const links = document.querySelectorAll("a");
  links.forEach((link) => {
    // console.log(link.pathname);
    link.addEventListener("mouseenter", function (event) {
      if (event && event.target && event.target instanceof HTMLAnchorElement) {
        prefetchIfNeeded(event.target);
      } else {
        // console.log("Couldn't prefetch with event", event);
      }
    });
  });
}

function prefetchIfNeeded(/** @type {HTMLAnchorElement} */ target) {
  if (target.host === window.location.host) {
    if (prefetchedPages.includes(target.pathname)) {
      // console.log("Already preloaded", target.href);
      // console.log("Not a known route, skipping preload", target.pathname);
    } else if (
      !allRoutes.includes(new URL(target.pathname, document.baseURI).href)
    ) {
    } else {
      prefetchedPages.push(target.pathname);
      // console.log("Preloading...", target.pathname);
      const link = document.createElement("link");
      link.setAttribute("as", "fetch");

      link.setAttribute("rel", "prefetch");
      link.setAttribute("href", origin + target.pathname + "/content.json");
      document.head.appendChild(link);
    }
  }
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

userInit(
  pagesInit({
    mainElmModule: Elm.Main,
  })
);

// function pagesInit(config) {
//   const path = window.location.pathname.replace(/(\w)$/, "$1/");

//   httpGet(`${window.location.origin}${path}content.json`).then(function (
//     /** @type {JSON} */ contentJson
//   ) {
//     const app = config.mainElmModule.init({
//       flags: {
//         secrets: null,
//         baseUrl: document.baseURI,
//         isPrerendering: false,
//         isDevServer: false,
//         isElmDebugMode: false,
//         contentJson,
//       },
//     });
//   });
// }

// function httpGet(/** @type string */ theUrl) {
//   return new Promise(function (resolve, reject) {
//     const xmlHttp = new XMLHttpRequest();
//     xmlHttp.onreadystatechange = function () {
//       if (xmlHttp.readyState == 4 && xmlHttp.status == 200)
//         resolve(JSON.parse(xmlHttp.responseText));
//     };
//     xmlHttp.onerror = reject;
//     xmlHttp.open("GET", theUrl, true); // true for asynchronous
//     xmlHttp.send(null);
//   });
// }
