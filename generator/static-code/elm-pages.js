import userInit from "/index.js";

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

const appPromise = pagesInit({
  mainElmModule: Elm.TemplateModulesBeta,
});
userInit(appPromise);

connect(function (onContentJsonError, onOk) {
  appPromise.then((app) => {
    app.ports.fromJsPort.send({ action: "hmr-check" });
    let currentPath = window.location.pathname.replace(/(\w)$/, "$1/");
    fetch(`${window.location.origin}${currentPath}content.json`).then(
      async function (contentJson) {
        console.log("ok?", contentJson.ok);
        if (contentJson.ok) {
          app.ports.fromJsPort.send({ contentJson: await contentJson.json() });
          onOk();
        } else {
          try {
            onContentJsonError(await contentJson.json());
          } catch (error) {
            console.log("Invalid JSON response for content.json", error);
            onOk();
          }
        }
      }
    );
  });
});
