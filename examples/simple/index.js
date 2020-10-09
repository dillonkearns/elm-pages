// @ts-ignore
const { Elm } = require("./src/Main.elm");
const pagesInit = require("../../index.js");

pagesInit({
  mainElmModule: Elm.Main
});
