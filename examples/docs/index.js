import "elm-oembed";
import "./style.css";
import "./syntax.css";

// @ts-ignore
const { Elm } = require("./src/Main.elm");
const pagesInit = require("../../index.js");

pagesInit({
  mainElmModule: Elm.Main
});
