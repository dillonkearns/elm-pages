import "elm-oembed";
import "./lib/code-editor.js";
import "./style.css";
// @ts-ignore
const { Elm } = require("./src/Main.elm");
const pagesInit = require("elm-pages");
// const pagesInit = require("../../index.js").default;

pagesInit({
  mainElmModule: Elm.Main
});
