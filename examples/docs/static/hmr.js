console.log("Loaded HMR");
var eventSource = null;

/** @type {Promise<() => void>} */
let updateAppContentJson = new Promise((resolve, reject) => resolve(() => {}));

function connect(sendContentJsonPort) {
  // Listen for the server to tell us that an HMR update is available
  eventSource = new EventSource("stream");
  eventSource.onmessage = async function (evt) {
    showCompiling("");
    if (evt.data === "content.json") {
      const elmJsRequest = elmJsFetch();
      const fetchContentJson = fetchContentJsonForCurrentPage();
      updateAppContentJson = updateContentJsonWith(
        fetchContentJson,
        sendContentJsonPort
      );

      try {
        await fetchContentJson;
        const elmJsResponse = await elmJsRequest;
        thenApplyHmr(elmJsResponse);
      } catch (errorJson) {
        console.log({ errorJson });
        showError({
          type: "compile-errors",
          errors: errorJson,
        });
      }
    } else {
      elmJsFetch().then(thenApplyHmr);
    }
  };
}

/**
 *
 * @param {*} fetchContentJsonPromise
 * @param {*} sendContentJsonPort
 * @returns {Promise<() => void>}
 */
async function updateContentJsonWith(
  fetchContentJsonPromise,
  sendContentJsonPort
) {
  return new Promise(async (resolve, reject) => {
    try {
      const newContentJson = await fetchContentJsonPromise;
      hideError();

      resolve(() => {
        sendContentJsonPort(newContentJson);
        hideCompiling("fast");
      });
    } catch (errorJson) {
      showError({
        type: "compile-errors",
        errors: errorJson,
      });
    }
  });
}

function fetchContentJsonForCurrentPage() {
  return new Promise(async (resolve, reject) => {
    let currentPath = window.location.pathname.replace(/(\w)$/, "$1/");

    const contentJsonForPage = await fetch(
      `${window.location.origin}${currentPath}content.json`
    );
    if (contentJsonForPage.ok) {
      resolve(await contentJsonForPage.json());
    } else {
      resolve(null);
    }
  });
}

// Expose the Webpack HMR API

// var myDisposeCallback = null;
var myDisposeCallback = function () {
  console.log("dispose...");
};

// simulate the HMR api exposed by webpack
var module = {
  hot: {
    accept: async function () {
      const sendInUpdatedContentJson = await updateAppContentJson;
      sendInUpdatedContentJson();
    },

    dispose: function (callback) {
      myDisposeCallback = callback;
    },

    data: null,

    apply: function () {
      var newData = {};
      myDisposeCallback(newData);
      module.hot.data = newData;
    },

    verbose: true,
  },
};

// Thanks to the elm-live maintainers and contributors for this code for rendering errors as an HTML overlay
// https://github.com/wking-io/elm-live/blob/e317b4914c471addea7243c47f28dcebe27a5d36/lib/src/websocket.js

const pipe = (...fns) => (x) => fns.reduce((y, f) => f(y), x);

function elmJsFetch() {
  var elmJsRequest = new Request("/elm.js");
  elmJsRequest.cache = "no-cache";
  return fetch(elmJsRequest);
}

async function waitFor(millis) {
  return new Promise((resolve) => {
    setTimeout(resolve, millis);
  });
}

async function thenApplyHmr(response) {
  if (response.ok) {
    response.text().then(function (value) {
      module.hot.apply();
      delete Elm;
      eval(value);
    });
  } else {
    try {
      const errorJson = await response.json();
      console.error("JSON", errorJson);
      showError(errorJson);
    } catch (jsonParsingError) {
      console.log("Couldn't parse error", jsonParsingError);
    }
  }
}

function colorConverter(color) {
  return {
    black: "#000000",
    red: "#F77F00",
    green: "#33ff00",
    yellow: "#ffff00",
    blue: "#99B1BC",
    magenta: "#cc00ff",
    cyan: "#00ffff",
    white: "#d0d0d0",
    BLACK: "#808080",
    RED: "#ff0000",
    GREEN: "#33ff00",
    YELLOW: "#ffff00",
    BLUE: "#0066ff",
    MAGENTA: "#cc00ff",
    CYAN: "#00ffff",
    WHITE: "#ffffff",
  }[color];
}

const addNewLine = (str) => str + "\n";
const styleColor = (str = "WHITE") => `color: ${colorConverter(str)};`;
const styleUnderline = `text-decoration: underline;`;
const styleBold = `text-decoration: bold;`;
const parseStyle = ({ underline, color, bold }) =>
  `${underline ? styleUnderline : ""}${color ? styleColor(color) : ""}${
    bold ? styleBold : ""
  }`;

function capitalizeFirstLetter(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function consoleSanitize(str) {
  return str.replace(/<(http[^>]*)>/, "$1");
}

function htmlSanitize(str, type) {
  var temp = document.createElement("div");
  temp.textContent = str;
  return temp.innerHTML.replace(
    /&lt;(http[^>]*)&gt;/,
    "&lt;<a style='color: inherit' target='_blank' href='$1'>$1</a>&gt;"
  );
}

const parseHeader = (title, path) =>
  `-- ${title.replace("-", " ")} --------------- ${path}`;

/*
  |-------------------------------------------------------------------------------
  | Console Logging
  |-------------------------------------------------------------------------------
  */

const wrapConsole = (str) => `%c${str}`;
const consoleHeader = pipe(parseHeader, wrapConsole, addNewLine, addNewLine);

const parseMsg = pipe(consoleSanitize, wrapConsole);
const consoleMsg = ({ error, style }, msg) => ({
  error: error.concat(parseMsg(typeof msg === "string" ? msg : msg.string)),
  style: style.concat(
    parseStyle(typeof msg === "string" ? { color: "black" } : msg)
  ),
});

const joinMessage = ({ error, style }) => [error.join("")].concat(style);

const parseConsoleErrors = (path) => ({ title, message }) =>
  joinMessage(
    message.reduce(consoleMsg, {
      error: [consoleHeader(title, path)],
      style: [styleColor("blue")],
    })
  );

const restoreColorConsole = ({ errors }) =>
  errors.reduce(
    (acc, { problems, path }) =>
      acc.concat(problems.map(parseConsoleErrors(path))),
    []
  );

/*
  |-------------------------------------------------------------------------------
  | Html Logging
  |-------------------------------------------------------------------------------
  */

const htmlHeader = (title, path) =>
  `<span style="${parseStyle({ color: "blue" })}">${parseHeader(
    title,
    path
  )}</span>\n\n`;

const htmlMsg = (acc, msg) =>
  `${acc}<span style="${parseStyle(
    typeof msg === "string" ? { color: "WHITE" } : msg
  )}">${htmlSanitize(typeof msg === "string" ? msg : msg.string)}</span>`;

const parseHtmlErrors = (path) => ({ title, message }) =>
  message.reduce(htmlMsg, htmlHeader(title, path));

const restoreColorHtml = ({ errors }) =>
  errors.reduce(
    (acc, { problems, path }) =>
      acc.concat(problems.map(parseHtmlErrors(path))),
    []
  );

/*
  |-------------------------------------------------------------------------------
  | TODO: Refactor Below
  |-------------------------------------------------------------------------------
  */

var speed = 400;
var delay = 20;

function showError(error) {
  restoreColorConsole(error).forEach((error) => {
    console.log.apply(this, error);
  });
  hideCompiling("fast");
  setTimeout(function () {
    showError_(restoreColorHtml(error));
  }, delay);
}

function showError_(error) {
  var nodeContainer = document.getElementById("elm-live:elmErrorContainer");

  if (!nodeContainer) {
    nodeContainer = document.createElement("div");
    nodeContainer.id = "elm-live:elmErrorContainer";
    document.body.appendChild(nodeContainer);
  }

  nodeContainer.innerHTML = `
<div
  id="elm-live:elmErrorBackground"
  style="
    z-index: 100;
    perspective: 500px;
    transition: opacity 400ms;
    position: fixed;
    top: 0;
    left: 0;
    background-color: rgba(13,31,45,0.2);
    width: 100%;
    height: 100%;
    display: flex;
    justify-content:center;
    align-items: center;
  "
>
  <div
    onclick="elmLive.hideError()"
    style="
      background-color: rgba(0,0,0,0);
      position: fixed;
      top:0;
      left:0;
      bottom:0;
      right:0
    "
  ></div>
  <pre
    id="elm-live:elmError"
    style="
      white-space: pre-wrap;
      transform: rotateX(0deg);
      transition: transform 400ms;
      transform-style: preserve-3d;
      font-size: 16px;
      overflow: scroll;
      background-color: rgba(13, 31, 45, 0.9);
      color: #ddd;
      width: calc(100% - 150px);
      height: calc(100% - 150px);
      margin: 0;
      padding: 30px;
      font-family: 'Fira Mono', Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;
    "
  >${error}</pre>
</div>
`;

  setTimeout(function () {
    document.getElementById("elm-live:elmErrorBackground").style.opacity = 1;
    document.getElementById("elm-live:elmError").style.transform =
      "rotateX(0deg)";
  }, delay);
}

function hideError(velocity) {
  var node = document.getElementById("elm-live:elmErrorContainer");
  if (node) {
    if (velocity === "fast") {
      document.getElementById("elm-live:elmErrorContainer").remove();
    } else {
      document.getElementById("elm-live:elmErrorBackground").style.opacity = 0;
      document.getElementById("elm-live:elmError").style.transform =
        "rotateX(90deg)";
      setTimeout(function () {
        document.getElementById("elm-live:elmErrorContainer").remove();
      }, speed);
    }
  }
}

function showCompiling(message) {
  hideError("fast");
  setTimeout(function () {
    showCompiling_(message);
  }, delay);
}

function showCompiling_(message) {
  var nodeContainer = document.getElementById("__elm-pages-loading");

  if (!nodeContainer) {
    nodeContainer = document.createElement("div");
    nodeContainer.id = "__elm-pages-loading";
    nodeContainer.class = "lds-default";
    nodeContainer.style = `
                              position: fixed;
                              bottom: 10px;
                              right: 110px;
                              width: 80px;
                              height: 80px;
                              background-color: white;
                              display: block;
                              box-shadow: rgba(0, 0, 0, 0.25) 0px 8px 15px 0px,
                                rgba(0, 0, 0, 0.12) 0px 2px 10px 0px;
                            `;
    document.body.appendChild(nodeContainer);
  }

  nodeContainer.innerHTML = `
  <div
    style="
      animation: 1.2s linear 0s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 37px;
      left: 66px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.1s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 22px;
      left: 62px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.2s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 11px;
      left: 52px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.3s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 7px;
      left: 37px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.4s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 11px;
      left: 22px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.5s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 22px;
      left: 11px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.6s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 37px;
      left: 7px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.7s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 52px;
      left: 11px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.8s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 62px;
      left: 22px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -0.9s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 66px;
      left: 37px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -1s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 62px;
      left: 52px;
    "
  ></div>
  <div
    style="
      animation: 1.2s linear -1.1s infinite normal none running lds-default;
      background: rgb(0, 0, 0);
      position: absolute;
      width: 6px;
      height: 6px;
      border-radius: 50%;
      top: 52px;
      left: 62px;
    "
  ></div>
`;
  setTimeout(function () {
    document.getElementById("__elm-pages-loading").style.opacity = 1;
  }, delay);
}

function hideCompiling(velocity) {
  const node = document.getElementById("__elm-pages-loading");
  if (node) {
    if (velocity === "fast") {
      node.remove();
    } else {
      document.getElementById("__elm-pages-loading").style.opacity = 0;
      setTimeout(function () {
        node.remove();
      }, speed);
    }
  }
}
