console.log("Loaded HMR");
var eventSource = null;

function connect(refetchContentJson) {
  // Listen for the server to tell us that an HMR update is available
  eventSource = new EventSource("stream");
  eventSource.onmessage = function (evt) {
    if (evt.data === "content.json") {
      refetchContentJson();
    } else {
      var reloadUrl = evt.data;
      var myRequest = new Request(reloadUrl);
      myRequest.cache = "no-cache";
      fetch(myRequest).then(async function (response) {
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
          } catch (jsonParsingError) {
            console.log("Couldn't parse error", jsonParsingError);
          }
        }
      });
    }
  };
}

// Expose the Webpack HMR API

// var myDisposeCallback = null;
var myDisposeCallback = function () {
  console.log("dispose...");
};

// simulate the HMR api exposed by webpack
var module = {
  hot: {
    accept: function () {},

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
