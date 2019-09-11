import "elm-oembed";
import "./lib/code-editor.js";
import "./style.css";
const { Elm } = require("./src/Main.elm");
const pagesInit = require("elm-pages");

pagesInit({
  mainElmModule: Elm.Main
});
