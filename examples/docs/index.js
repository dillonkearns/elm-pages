import "elm-oembed";
import "./lib/code-editor.js";
import "./style.css";
const { Elm } = require("./src/Main.elm");
// const pagesInit = require("elm-pages");
const pagesInit = require("../../index.js");

pagesInit({
  mainElmModule: Elm.Main
});
