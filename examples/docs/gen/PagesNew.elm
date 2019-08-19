port module PagesNew exposing (..)

import Dict exposing (Dict)
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Mark
import Pages.ContentCache exposing (Page)
import Pages.Manifest


port toCli : Json.Encode.Value -> Cmd msg


type alias Flags =
    Json.Decode.Value


encodeForRenderer manifest =
    Pages.Manifest.toJson manifest


type Msg userMsg metadata view
    = SendToCompileTimeRenderer Json.Encode.Value


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


type alias Program userModel userMsg metadata view =
    Platform.Program Flags (Model userModel userMsg metadata view) (Msg userMsg metadata view)


application :
    { init : ( userModel, Cmd userMsg )
    , update : userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : userModel -> Sub userMsg
    , view : userModel -> List ( List String, metadata ) -> Page metadata view -> { title : String, body : Html userMsg }
    , parser : Parser metadata view
    , content : Content
    , toJsPort : Json.Encode.Value -> Cmd (Msg userMsg metadata view)
    , head : metadata -> List Head.Tag
    , frontmatterParser : Json.Decode.Decoder metadata
    , markdownToHtml : String -> view
    , manifest : Pages.Manifest.Config
    }
    -> Program userModel userMsg metadata view
application config =
    Platform.worker
        { init =
            \flags ->
                ( Model
                , toCli (encodeForRenderer config.manifest)
                )
        , update = \msg model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
