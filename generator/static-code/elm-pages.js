import userInit from "/index.js";

let prefetchedPages;
let initialLocationHash;

function pagesInit(
  /** @type { mainElmModule: { init: any  } } */ { mainElmModule }
) {
  prefetchedPages = [window.location.pathname];
  initialLocationHash = document.location.hash.replace(/^#/, "");

  return new Promise(function (resolve, reject) {
    document.addEventListener("DOMContentLoaded", (_) => {
      loadContentAndInitializeApp(mainElmModule).then(resolve, reject);
    });
  });
}

function getContentJsonPromise(path) {
  return new Promise((resolve, reject) => {
    if (window.__elmPagesContentJson__) {
      console.log("GOT content.json from window");
      resolve(window.__elmPagesContentJson__);
    } else {
      return httpGet(`${window.location.origin}${path}content.json`);
    }
  });
}

function loadContentAndInitializeApp(
  /** @type { init: any  } */ mainElmModule
) {
  let path = window.location.pathname.replace(/(\w)$/, "$1/");
  if (!path.endsWith("/")) {
    path = path + "/";
  }

  return Promise.all([getContentJsonPromise(path)]).then(function (
    /** @type {[JSON]} */ [contentJson]
  ) {
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

    app.ports.toJsPort.subscribe((fromElm) => {
      loadNamedAnchor();
    });

    return app;
  });
}

function loadNamedAnchor() {
  if (initialLocationHash !== "") {
    const namedAnchor = document.querySelector(`[name=${initialLocationHash}]`);
    namedAnchor && namedAnchor.scrollIntoView();
  }
}

function prefetchIfNeeded(/** @type {HTMLAnchorElement} */ target) {
  if (target.host === window.location.host) {
    if (prefetchedPages.includes(target.pathname)) {
      // console.log("Already preloaded", target.href);
      // console.log("Not a known route, skipping preload", target.pathname);
    } else if (
      // !allRoutes.includes(new URL(target.pathname, document.baseURI).href)
      false
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

const appPromise = pagesInit({
  mainElmModule: Elm.TemplateModulesBeta,
});
userInit(appPromise);

if (typeof connect === "function") {
  connect(function (newContentJson) {
    appPromise.then((app) => {
      app.ports.fromJsPort.send({ contentJson: newContentJson });
    });
  });
}

/** @param {MouseEvent} event */
const trigger_prefetch = (event) => {
  const a = find_anchor(/** @type {Node} */ (event.target));
  if (a && a.href && a.hasAttribute("elm-pages:prefetch")) {
    console.log("PREFETCH", a.href);
    prefetchIfNeeded(a);
    // this.prefetch(new URL(/** @type {string} */ (a.href)));
  }
};

/** @type {NodeJS.Timeout} */
let mousemove_timeout;

/** @param {MouseEvent} event */
const handle_mousemove = (event) => {
  clearTimeout(mousemove_timeout);
  mousemove_timeout = setTimeout(() => {
    trigger_prefetch(event);
  }, 20);
};

addEventListener("touchstart", trigger_prefetch);
addEventListener("mousemove", handle_mousemove);

/**
 * @param {Node} node
//  * @rturns {HTMLAnchorElement | SVGAElement}
 * @returns {HTMLAnchorElement}
 */
function find_anchor(node) {
  while (node && node.nodeName.toUpperCase() !== "A") node = node.parentNode; // SVG <a> elements have a lowercase name
  // return /** @type {HTMLAnchorElement | SVGAElement} */ (node);
  return /** @type {HTMLAnchorElement} */ (node);
}
