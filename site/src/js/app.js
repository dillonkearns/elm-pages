import { Elm } from "../Main.elm";

document.addEventListener("DOMContentLoaded", function() {
  Elm.Main.init({
    node: document.getElementById("app")
  });
});
