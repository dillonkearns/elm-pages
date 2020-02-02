import "elm-oembed";
import "./style.css";
import "./syntax.css";

// @ts-ignore
const { Elm } = require("./src/Main.elm");
const pagesInit = require("../../index.js");

if (window.CMS_MANUAL_INIT) {
  import('./src/preview.js' /* webpackChunkName: "admin" */)
} else {
  Promise.all([
    import('./src/Main.elm' /* webpackChunkName: "site" */),
    import('elm-pages' /* webpackChunkName: "site" */),
  ]).then(([{ Elm }, { default: pagesInit }]) => {
    setTimeout(() => {
      pagesInit({
        mainElmModule: Elm.Main
      })
      document.dispatchEvent(new Event('DOMContentLoaded'))
    }, 0)
  })
}
