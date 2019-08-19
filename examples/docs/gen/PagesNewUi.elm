port module PagesNewUi exposing (..)

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


type alias Flags =
    Json.Decode.Value


type alias Parser metadata view =
    Dict String String
    -> List String
    -> List ( List String, metadata )
    -> Mark.Document (Page metadata view)


type alias Content =
    { markdown : List ( List String, { frontMatter : String, body : Maybe String } )
    , markup : List ( List String, String )
    }


type Model userModel userMsg metadata view
    = Model


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , parser : Parser metadata view
    , head : metadata -> List Head.Tag
    , frontmatterParser : Json.Decode.Decoder metadata
    , markdownToHtml : String -> view
    , manifest : Pages.Manifest.Config
    }
    -> Pages.Program userModel userMsg metadata view
application config =
    Pages.application
        { init = config.init
        , view = config.view
        , update = config.update
        , subscriptions = config.subscriptions
        , parser = config.parser
        , frontmatterParser = config.frontmatterParser
        , content = content
        , markdownToHtml = config.markdownToHtml
        , toJsPort = toJsPort
        , head = config.head
        , manifest = config.manifest
        }


content : Content
content =
    RawContent.content
