const fs = require("fs");
const runElm = require("./compile-elm.js");
const copyModifiedElmJson = require("./rewrite-elm-json.js");

const elmPagesCliFile = `port module PagesNew exposing (application)

import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Mark
import Pages
import Pages.ContentCache exposing (Page)
import Pages.Manifest
import RawContent


port toJsPort : Json.Encode.Value -> Cmd msg


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , parser : Pages.Parser metadata view
    , head : metadata -> List Head.Tag
    , frontmatterParser : Json.Decode.Decoder metadata
    , markdownToHtml : String -> view
    , manifest : Pages.Manifest.Config
    }
    -> Pages.Program userModel userMsg metadata view
application config =
    Pages.cliApplication
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , parser = config.parser
        , frontmatterParser = config.frontmatterParser
        , content = RawContent.content
        , markdownToHtml = config.markdownToHtml
        , toJsPort = toJsPort
        , head = config.head
        , manifest = config.manifest
        }
`;

module.exports = function run() {
  // mkdir -p elm-stuff/elm-pages/
  // requires NodeJS >= 10.12.0
  fs.mkdirSync("./elm-stuff/elm-pages", { recursive: true });

  // write `PagesNew.elm` with cli interface
  fs.writeFileSync("./elm-stuff/elm-pages/PagesNew.elm", elmPagesCliFile);

  // generate RawContent.elm
  // TODO

  // write modified elm.json to elm-stuff/elm-pages/
  copyModifiedElmJson();

  // run Main.elm from elm-stuff/elm-pages with `runElm`
  runElm(function(payload) {
    console.log("Received payload!", payload);
  });
};
