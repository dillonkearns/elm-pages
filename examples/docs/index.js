// import { Elm } from "../Main.elm";
import "./style.css";
const { Elm } = require("./src/Main.elm");
const pagesInit = require("elm-pages");
// import { imageAssets } from "./image-assets";

const imageAssets = {};

pagesInit({
  mainElmModule: Elm.Main,
  imageAssets
});
