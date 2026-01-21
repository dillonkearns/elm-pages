import userInit from "/index";
import { initStaticRegions, prefetchStaticRegions, fetchStaticRegions } from "./static-regions-client.js";

let prefetchedPages;
let initialLocationHash;
/**
 * @returns
 */
function loadContentAndInitializeApp() {
  // Initialize static regions - on initial load, they're adopted from existing DOM
  initStaticRegions();

  let path = window.location.pathname.replace(/(\w)$/, "$1/");
  if (!path.endsWith("/")) {
    path = path + "/";
  }
  const app = Elm.Main.init({
    flags: {
      secrets: null,
      isPrerendering: false,
      isDevServer: false,
      isElmDebugMode: false,
      contentJson: {},
      pageDataBase64: document.getElementById("__ELM_PAGES_BYTES_DATA__")
        .innerHTML,
      userFlags: userInit.flags(),
    },
  });

  app.ports.toJsPort.subscribe(async (fromElm) => {
    if (fromElm.tag === "FetchStaticRegions") {
      // Fetch static regions for the given path, then notify Elm
      await fetchStaticRegions(fromElm.path);
      app.ports.fromJsPort.send({ tag: "StaticRegionsReady" });
    } else {
      loadNamedAnchor();
    }
  });

  return app;
}

function loadNamedAnchor() {
  if (initialLocationHash !== "") {
    const namedAnchor = document.querySelector(`[name=${initialLocationHash}]`);
    namedAnchor && namedAnchor.scrollIntoView();
  }
}

function prefetchIfNeeded(/** @type {HTMLAnchorElement} */ target) {
  if (
    target.host === window.location.host &&
    !prefetchedPages.includes(target.pathname)
  ) {
    prefetchedPages.push(target.pathname);
    const link = document.createElement("link");
    link.setAttribute("as", "fetch");

    link.setAttribute("rel", "prefetch");
    link.setAttribute("href", origin + target.pathname + "/content.dat");
    document.head.appendChild(link);

    // Also prefetch static regions for the page
    prefetchStaticRegions(target.pathname);
  }
}

export function setup() {
  prefetchedPages = [window.location.pathname];
  initialLocationHash = document.location.hash.replace(/^#/, "");
  const appPromise = new Promise(function (resolve, reject) {
    document.addEventListener("DOMContentLoaded", (_) => {
      resolve(loadContentAndInitializeApp());
    });
  });
  userInit.load(appPromise);

  if (typeof connect === "function") {
    connect(function (bytesData) {
      appPromise.then((app) => {
        app.ports.hotReloadData.send(bytesData);
      });
    });
  }

  /** @param {MouseEvent} event */
  const trigger_prefetch = (event) => {
    const a = find_anchor(/** @type {Node} */ (event.target));
    if (a && a.href && a.hasAttribute("elm-pages:prefetch")) {
      prefetchIfNeeded(a);
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
}

/**
 * @param {Node} node
//  * @rturns {HTMLAnchorElement | SVGAElement}
 * @returns {HTMLAnchorElement}
 */
function find_anchor(node) {
  while (node && node.nodeName.toUpperCase() !== "A") node = node.parentNode; // SVG <a> elements have a lowercase name
  return /** @type {HTMLAnchorElement} */ (node);
}

// only run in modern browsers to prevent exception: https://github.com/dillonkearns/elm-pages/issues/427
if ("SubmitEvent" in window) {
  Object.defineProperty(SubmitEvent.prototype, "fields", {
    get: function fields() {
      let formData = new FormData(this.currentTarget);
      if (this.submitter && this.submitter.name) {
        formData.append(this.submitter.name, this.submitter.value);
      }
      return [...formData.entries()];
    },
  });
}

setup();
