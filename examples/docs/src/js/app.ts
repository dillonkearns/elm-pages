// @ts-ignore
import { Elm } from "../Main.elm";
// @ts-ignore
import { imageAssets, routes } from "./image-assets";
import { pagesInit } from "./helper";

pagesInit({
  mainElmModule: Elm.Main,
  imageAssets,
  routes
});
