import userInit from "/index.js";

let prefetchedPages = [window.location.pathname];
let initialLocationHash = document.location.hash.replace(/^#/, "");

/**
 * @returns
 */
function loadContentAndInitializeApp() {
  let path = window.location.pathname.replace(/(\w)$/, "$1/");
  if (!path.endsWith("/")) {
    path = path + "/";
  }
  const app = Elm.TemplateModulesBeta.init({
    flags: {
      secrets: null,
      isPrerendering: false,
      isDevServer: false,
      isElmDebugMode: false,
      contentJson: JSON.parse(
        document.getElementById("__ELM_PAGES_DATA__").innerHTML
      ),
      userFlags: userInit.flags(),
    },
  });

  app.ports.toJsPort.subscribe((fromElm) => {
    loadNamedAnchor();
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
    link.setAttribute("href", origin + target.pathname + "/content.json");
    document.head.appendChild(link);
  }
}

const appPromise = new Promise(function (resolve, reject) {
  document.addEventListener("DOMContentLoaded", (_) => {
    resolve(loadContentAndInitializeApp());
  });
});

userInit.load(appPromise);

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

/**
 * @param {Node} node
//  * @rturns {HTMLAnchorElement | SVGAElement}
 * @returns {HTMLAnchorElement}
 */
function find_anchor(node) {
  while (node && node.nodeName.toUpperCase() !== "A") node = node.parentNode; // SVG <a> elements have a lowercase name
  return /** @type {HTMLAnchorElement} */ (node);
}
