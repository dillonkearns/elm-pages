import * as elmOembed from "/elm-oembed.js";
// import "./lib/native-shim.js";

export default function (elmLoaded) {
  document.addEventListener("DOMContentLoaded", function (event) {
    elmOembed.setup();
  });
}
