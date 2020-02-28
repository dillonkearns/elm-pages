const elmPagesVersion = require("./package.json").version;

let prefetchedPages;
let initialLocationHash;
let elmViewRendered = false;
let headTagsAdded = false;

module.exports = function pagesInit(
  /** @type { mainElmModule: { init: any  } } */ { mainElmModule }
) {
  prefetchedPages = [window.location.pathname];
  initialLocationHash = document.location.hash.replace(/^#/, "");

  return new Promise(function(resolve, reject) {
    document.addEventListener("DOMContentLoaded", _ => {
        new MutationObserver(function() {
          elmViewRendered = true;
          if (headTagsAdded) {
            document.dispatchEvent(new Event("prerender-trigger"));
          }
        }).observe(document.body, { attributes: true, childList: true, subtree: true});

      loadContentAndInitializeApp(mainElmModule).then(resolve, reject);
    });
  })
};

function loadContentAndInitializeApp(/** @type { init: any  } */ mainElmModule) {
  return httpGet(`${window.location.origin}${window.location.pathname}/content.json`).then(function(/** @type JSON */ contentJson) {

    const app = mainElmModule.init({
      flags: {
        secrets: null,
        isPrerendering: navigator.userAgent.indexOf("Headless") >= 0,
        contentJson
      }
    });

    app.ports.toJsPort.subscribe((
      /** @type { { head: HeadTag[], allRoutes: string[] } }  */ fromElm
    ) => {
      appendTag({
        name: "meta",
        attributes: [
          ["name", "generator"],
          ["content", `elm-pages v${elmPagesVersion}`]
        ]
      });
      window.allRoutes = fromElm.allRoutes;
      

      if (navigator.userAgent.indexOf("Headless") >= 0) {
        fromElm.head.forEach(headTag => {
          appendTag(headTag);
        });
          headTagsAdded = true;
          if (elmViewRendered) {
            document.dispatchEvent(new Event("prerender-trigger"));
          }
      } else {
        setupLinkPrefetching();
      }
    });


    if (module.hot) {
      module.hot.addStatusHandler(function(status) {
        if (status === 'idle') {
          console.log('Reloaded!!!!!!!!!!', status)
          app.ports.fromJsPort.send({});
        }
      });
    }

    return app

  });
}

function setupLinkPrefetching() {
  new MutationObserver(observeFirstRender).observe(document.body, {
    attributes: true,
    childList: true,
    subtree: true
  });
}

function loadNamedAnchor() {
  if (initialLocationHash !== "") {
    const namedAnchor = document.querySelector(
      `[name=${initialLocationHash}]`
    );
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
    subtree: false
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
  links.forEach(link => {
    // console.log(link.pathname);
    link.addEventListener("mouseenter", function(event) {
      if (
        event &&
        event.target &&
        event.target instanceof HTMLAnchorElement
      ) {
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
    } else if (!allRoutes.includes(target.pathname)) {
      // console.log("Not a known route, skipping preload", target.pathname);
    }
    else {
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

/** @typedef {{ name: string; attributes: string[][]; }} HeadTag */
function appendTag(/** @type {HeadTag} */ tagDetails) {
  const meta = document.createElement(tagDetails.name);
  tagDetails.attributes.forEach(([name, value]) => {
    meta.setAttribute(name, value);
  });
  document.getElementsByTagName("head")[0].appendChild(meta);
}

function httpGet(/** @type string */ theUrl) {
  return new Promise(function(resolve, reject) {
    const xmlHttp = new XMLHttpRequest();
    xmlHttp.onreadystatechange = function() {
        if (xmlHttp.readyState == 4 && xmlHttp.status == 200)
            resolve(JSON.parse(xmlHttp.responseText));
    }
    xmlHttp.onerror = reject;
    xmlHttp.open("GET", theUrl, true); // true for asynchronous
    xmlHttp.send(null);
  })
}
