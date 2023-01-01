module Shared exposing (Data, Model, Msg(..), SharedMsg(..), template)

import BackendTask
import Effect exposing (Effect)
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Flags
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Route exposing (Route)
import SharedTemplate exposing (SharedTemplate)
import View exposing (View)


template : SharedTemplate Msg Model Data msg
template =
    { init = init
    , update = update
    , view = view
    , data = data
    , subscriptions = subscriptions
    , onPageChange = Just OnPageChange
    }


type Msg
    = OnPageChange
        { path : Path
        , query : Maybe String
        , fragment : Maybe String
        }
    | SharedMsg SharedMsg


type alias Data =
    ()


type SharedMsg
    = NoOp


type alias Model =
    { showMobileMenu : Bool
    }


init :
    Pages.Flags.Flags
    ->
        Maybe
            { path :
                { path : Path
                , query : Maybe String
                , fragment : Maybe String
                }
            , metadata : route
            , pageUrl : Maybe PageUrl
            }
    -> ( Model, Effect Msg )
init flags maybePagePath =
    ( { showMobileMenu = False }
    , Effect.none
    )


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        OnPageChange _ ->
            ( { model | showMobileMenu = False }, Effect.none )

        SharedMsg globalMsg ->
            ( model, Effect.none )


subscriptions : Path -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : BackendTask.BackendTask Data
data =
    BackendTask.succeed ()


view :
    Data
    ->
        { path : Path
        , route : Maybe Route
        }
    -> Model
    -> (Msg -> msg)
    -> View msg
    -> { body : Html msg, title : String }
view sharedData page model toMsg pageView =
    { body = Html.div [] (headerView :: pageView.body)
    , title = pageView.title
    }


headerView : Html msg
headerView =
    Html.header
        [ Attr.class "header"
        ]
        [ Html.nav
            [ Attr.class "inner"
            ]
            [ Html.a
                [ Attr.href "/"
                ]
                [ Html.strong []
                    [ Html.text "HN" ]
                ]
            , Html.a
                [ Attr.href "/new"
                ]
                [ Html.strong []
                    [ Html.text "New" ]
                ]
            , Html.a
                [ Attr.href "/show"
                ]
                [ Html.strong []
                    [ Html.text "Show" ]
                ]
            , Html.a
                [ Attr.href "/ask"
                ]
                [ Html.strong []
                    [ Html.text "Ask" ]
                ]
            , Html.a
                [ Attr.href "/job"
                ]
                [ Html.strong []
                    [ Html.text "Jobs" ]
                ]
            , Html.a
                [ Attr.class "github"
                , Attr.href "https://github.com/dillonkearns/elm-pages"
                , Attr.target "_blank"
                , Attr.rel "noreferrer"
                ]
                [ Html.text "Built with elm-pages" ]
            ]
        ]
