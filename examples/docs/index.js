import "./style.css";
const { Elm } = require("./src/Main.elm");
const pagesInit = require("elm-pages");

const imageAssets = {};

pagesInit({
  mainElmModule: Elm.Main,
  imageAssets
});
