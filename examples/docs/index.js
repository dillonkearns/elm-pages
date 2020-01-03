import "elm-oembed";
import "./lib/code-editor.js";
import "./style.css";
// @ts-ignore
const { Elm } = require("./src/Main.elm");
const pagesInit = require("../../index.js");

pagesInit({
  mainElmModule: Elm.Main
});
