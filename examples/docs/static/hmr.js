console.log("Loaded HMR");
var eventSource = null;

function connect() {
  // Listen for the server to tell us that an HMR update is available
  eventSource = new EventSource("stream");
  eventSource.onmessage = function (evt) {
    var reloadUrl = evt.data;
    var myRequest = new Request(reloadUrl);
    myRequest.cache = "no-cache";
    fetch(myRequest).then(function (response) {
      if (response.ok) {
        response.text().then(function (value) {
          module.hot.apply();
          delete Elm;
          eval(value);
        });
      } else {
        console.error(
          "HMR fetch failed:",
          response.status,
          response.statusText
        );
      }
    });
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

connect();

console.log("Called connect() from HMR");
