export function setup() {
  customElements.define(
    "oembed-element",
    class extends HTMLElement {
      connectedCallback() {
        let shadow = this.attachShadow({ mode: "closed" });
        const urlAttr = this.getAttribute("url");
        if (urlAttr) {
          renderOembed(shadow, urlAttr, {
            maxwidth: this.getAttribute("maxwidth"),
            maxheight: this.getAttribute("maxheight"),
          });
        } else {
          const discoverUrl = this.getAttribute("discover-url");
          if (discoverUrl) {
            getDiscoverUrl(discoverUrl, function (discoveredUrl) {
              if (discoveredUrl) {
                renderOembed(shadow, discoveredUrl, null);
              }
            });
          }
        }
      }
    }
  );

  /**
   *
   * @param {ShadowRoot} shadow
   * @param {string} urlToEmbed
   * @param {{maxwidth: string?; maxheight: string?}?} options
   */
  function renderOembed(shadow, urlToEmbed, options) {
    let apiUrlBuilder = new URL(
      `https://cors-anywhere.herokuapp.com/${urlToEmbed}`
    );
    if (options && options.maxwidth) {
      apiUrlBuilder.searchParams.set("maxwidth", options.maxwidth);
    }
    if (options && options.maxheight) {
      apiUrlBuilder.searchParams.set("maxheight", options.maxheight);
    }
    const apiUrl = apiUrlBuilder.toString();
    httpGetAsync(apiUrl, (rawResponse) => {
      const response = JSON.parse(rawResponse);

      switch (response.type) {
        case "rich":
          tryRenderingHtml(shadow, response);
          break;
        case "video":
          tryRenderingHtml(shadow, response);
          break;
        case "photo":
          let img = document.createElement("img");
          img.setAttribute("src", response.url);
          if (options) {
            img.setAttribute(
              "style",
              `max-width: ${options.maxwidth}px; max-height: ${options.maxheight}px;`
            );
          }
          shadow.appendChild(img);
          break;
        default:
          break;
      }
    });
  }

  /**
 * @param {{
    height: ?number;
    width: ?number;
    html: any;
}} response
 * @param {ShadowRoot} shadow
 */
  function tryRenderingHtml(shadow, response) {
    if (response && typeof response.html) {
      let iframe = createIframe(response);
      shadow.appendChild(iframe);
      setTimeout(() => {
        let refetchedIframe = shadow.querySelector("iframe");
        if (refetchedIframe && !response.height) {
          refetchedIframe.setAttribute(
            "height",
            // @ts-ignore
            (iframe.contentWindow.document.body.scrollHeight + 10).toString()
          );
        }
        if (refetchedIframe && !response.width) {
          refetchedIframe.setAttribute(
            "width",
            // @ts-ignore
            (iframe.contentWindow.document.body.scrollWidth + 10).toString()
          );
        }
      }, 1000);
    }
  }

  /**
   * @param {{ height: number?; width: number?; html: string; }} response
   * @returns {HTMLIFrameElement}
   */
  function createIframe(response) {
    let iframe = document.createElement("iframe");
    iframe.setAttribute("border", "0");
    iframe.setAttribute("frameborder", "0");
    iframe.setAttribute("height", ((response.height || 500) + 20).toString());
    iframe.setAttribute("width", ((response.width || 500) + 20).toString());
    iframe.setAttribute("style", "max-width: 100%;");
    iframe.srcdoc = response.html;
    return iframe;
  }

  /**
   * @param {string} url
   * @param {{ (discoveredUrl: string?): void;}} callback
   */
  function getDiscoverUrl(url, callback) {
    let apiUrl = new URL(
      `https://cors-anywhere.herokuapp.com/${url}`
    ).toString();
    httpGetAsync(apiUrl, function (response) {
      let dom = document.createElement("html");
      dom.innerHTML = response;
      /** @type {HTMLLinkElement | null} */ const oembedTag = dom.querySelector(
        'link[type="application/json+oembed"]'
      );
      callback(oembedTag && oembedTag.href);
    });
  }

  /**
   * @param {string} theUrl
   * @param {{ (rawResponse: string): void }} callback
   */
  function httpGetAsync(theUrl, callback) {
    var xmlHttp = new XMLHttpRequest();
    xmlHttp.onreadystatechange = function () {
      if (xmlHttp.readyState == 4 && xmlHttp.status == 200)
        callback(xmlHttp.responseText);
    };
    xmlHttp.open("GET", theUrl, true); // true for asynchronous
    xmlHttp.send(null);
  }
}
