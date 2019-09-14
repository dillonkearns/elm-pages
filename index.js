module.exports = function pagesInit({ mainElmModule }) {
  let prefetchedPages = [window.location.pathname];

  document.addEventListener("DOMContentLoaded", function() {
    let app = mainElmModule.init({
      flags: {}
    });

    app.ports.toJsPort.subscribe(payload => {
      if (payload.event === "page-changed") {
        setupLinkPrefetching();
      } else {
        if (navigator.userAgent.indexOf("Headless") >= 0) {
          headTags.forEach(headTag => {
            appendTag(headTag);
          });
        } else {
          setupLinkPrefetching();
        }
      }

      document.dispatchEvent(new Event("prerender-trigger"));
    });
  });

  function setupLinkPrefetching() {
    setTimeout(setupLinkPrefetchingHelp, 1000);
  }

  function setupLinkPrefetchingHelp() {
    console.log("Setting up link hover prefetches...");
    const links = document.querySelectorAll("a");
    console.log("links", links);
    links.forEach(link => {
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
        console.log(
          origin,
          " + ",
          "content.txt",
          " = ",
          origin + target.pathname + "/content.txt"
        );
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
