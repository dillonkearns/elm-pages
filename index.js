const elmPagesVersion = require("./package.json").version;

module.exports = function pagesInit(
  /** @type { { mainElmModule: { init: any  } } } */ { mainElmModule }
) {
  const initialLocationHash = document.location.hash.replace(/^#/, "");
  let prefetchedPages = [window.location.pathname];

  document.addEventListener("DOMContentLoaded", function() {


  httpGet(`${window.location.pathname}content.json`, function (/** @type JSON */ contentJson) {
    let app = mainElmModule.init({
      flags: {
        secrets: null,
        isPrerendering: navigator.userAgent.indexOf("Headless") >= 0,
        contentJson
      }
    });

    app.ports.toJsPort.subscribe((
      /** @type { HeadTag[] } headTags */ headTags
    ) => {
      appendTag({
        name: "meta",
        attributes: [
          ["name", "generator"],
          ["content", `elm-pages v${elmPagesVersion}`]
        ]
      });
      if (navigator.userAgent.indexOf("Headless") >= 0) {
        headTags.forEach(headTag => {
          appendTag(headTag);
        });
      } else {
        setupLinkPrefetching();
      }

      document.dispatchEvent(new Event("prerender-trigger"));
    });

  })

  });

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
          console.log("Couldn't prefetch with event", event);
        }
      });
    });
  }

  function prefetchIfNeeded(/** @type {HTMLAnchorElement} */ target) {
    if (target.host === window.location.host) {
      if (prefetchedPages.includes(target.pathname)) {
        // console.log("Already preloaded", target.href);
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

  /** @typedef {{ name: string; attributes: string[][]; }} HeadTag */
  function appendTag(/** @type {HeadTag} */ tagDetails) {
    const meta = document.createElement(tagDetails.name);
    tagDetails.attributes.forEach(([name, value]) => {
      meta.setAttribute(name, value);
    });
    document.getElementsByTagName("head")[0].appendChild(meta);
  }
};

function httpGet(/** @type string */ theUrl, /** @type Function */ callback)
{
    var xmlHttp = new XMLHttpRequest();
    xmlHttp.onreadystatechange = function() { 
        if (xmlHttp.readyState == 4 && xmlHttp.status == 200)
            callback(JSON.parse(xmlHttp.responseText));
    }
    xmlHttp.open("GET", theUrl, true); // true for asynchronous 
    xmlHttp.send(null);
}
