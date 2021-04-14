module Shared exposing (Model, Msg(..), SharedMsg(..), StaticData, template)

import Document exposing (Document)
import Html exposing (Html)
import OptimizedDecoder as D
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Secrets
import SharedTemplate exposing (SharedTemplate)


template : SharedTemplate Msg Model StaticData msg
template =
    { init = init
    , update = update
    , view = view
    , staticData = staticData
    , subscriptions = subscriptions
    , onPageChange = Just OnPageChange
    }


type Msg
    = OnPageChange
        { path : PagePath
        , query : Maybe String
        , fragment : Maybe String
        }
    | SharedMsg SharedMsg


type alias StaticData =
    Int


type SharedMsg
    = NoOp


type alias Model =
    { showMobileMenu : Bool
    }


init :
    Maybe
        { path :
            { path : PagePath
            , query : Maybe String
            , fragment : Maybe String
            }
        , metadata : route
        }
    -> ( Model, Cmd Msg )
init maybePagePath =
    ( { showMobileMenu = False
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnPageChange _ ->
            ( { model | showMobileMenu = False }, Cmd.none )

        SharedMsg globalMsg ->
            ( model, Cmd.none )


subscriptions : PagePath -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


staticData : StaticHttp.Request StaticData
staticData =
    StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (D.field "stargazers_count" D.int)


view :
    StaticData
    ->
        { path : PagePath
        , frontmatter : route
        }
    -> Model
    -> (Msg -> msg)
    -> Document msg
    -> { body : Html msg, title : String }
view stars page model toMsg pageView =
    { body =
        Html.text "Hi"
    , title = pageView.title
    }
