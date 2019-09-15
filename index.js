module.exports = function pagesInit({ mainElmModule }) {
  let prefetchedPages = [window.location.pathname];

  document.addEventListener("DOMContentLoaded", function() {
    let app = mainElmModule.init({
      flags: {}
    });

    app.ports.toJsPort.subscribe(payload => {
      if (navigator.userAgent.indexOf("Headless") >= 0) {
        headTags.forEach(headTag => {
          appendTag(headTag);
        });
      } else {
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

  function observeFirstRender(mutationList, firstRenderObserver) {
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
  function observeUrlChanges(mutationList, theObserver) {
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

  function setupLinkPrefetchingHelp(mutationList, theObserver) {
    const links = document.querySelectorAll("a");
    window.links = links;
    console.log("LINKS");
    links.forEach(link => {
      console.log(link.pathname);
      link.addEventListener("mouseenter", function(event) {
        if (event && event.target) {
          prefetchIfNeeded(event.target);
        } else {
          console.log("Couldn't prefetch with event", event);
        }
      });
    });
  }

  function prefetchIfNeeded(target) {
    if (target.host === window.location.host) {
      if (prefetchedPages.includes(target.pathname)) {
        console.log("Already preloaded", event.target.href);
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

  function appendTag(tagDetails) {
    const meta = document.createElement(tagDetails.name);
    tagDetails.attributes.forEach(([name, value]) => {
      meta.setAttribute(name, value);
    });
    document.getElementsByTagName("head")[0].appendChild(meta);
  }
};
