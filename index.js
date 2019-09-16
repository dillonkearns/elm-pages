// @ts-ignore
const elmPagesVersion = require("./package.json").version;

module.exports = function pagesInit(
  /** @type { { mainElmModule: { init: any  } } } */ { mainElmModule }
) {
  let prefetchedPages = [window.location.pathname];

  document.addEventListener("DOMContentLoaded", function() {
    let app = mainElmModule.init({
      flags: {}
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
        console.log("headTags", headTags);

        headTags.forEach(headTag => {
          appendTag(headTag);
        });
        setupLinkPrefetching();
      }

      document.dispatchEvent(new Event("prerender-trigger"));
    });
  });

  function setupLinkPrefetching() {
    new MutationObserver(observeFirstRender).observe(document.body, {
      attributes: true,
      childList: true,
      subtree: true
    });
  }

  function observeFirstRender(
    /** @type {MutationRecord[]} */ mutationList,
    /** @type {MutationObserver} */ firstRenderObserver
  ) {
    for (let mutation of mutationList) {
      if (mutation.type === "childList") {
        console.log(
          "Setting up prefetch links for ",
          mutation.target.attributes["data-url"]
        );
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
      if (mutation.type === "attributes") {
        console.log(
          "Setting up prefetch links for ",
          mutation.target.attributes["data-url"]
        );
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
        console.log("Already preloaded", target.href);
      } else {
        prefetchedPages.push(target.pathname);
        console.log("Preloading...", target.pathname);
        const link = document.createElement("link");
        link.setAttribute("rel", "prefetch");
        link.setAttribute("href", origin + target.pathname + "/content.txt");
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
