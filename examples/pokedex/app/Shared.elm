module Shared exposing (Data, Model, Msg(..), SharedMsg(..), template)

import DataSource
import Effect exposing (Effect)
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Effect
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
    -> ( Model, Pages.Effect.Effect Msg (Effect Msg) )
init flags maybePagePath =
    ( { showMobileMenu = False }
    , Pages.Effect.none
    )


update : Msg -> Model -> ( Model, Pages.Effect.Effect Msg (Effect Msg) )
update msg model =
    case msg of
        OnPageChange _ ->
            ( { model | showMobileMenu = False }, Pages.Effect.none )

        SharedMsg globalMsg ->
            ( model, Pages.Effect.none )


subscriptions : Path -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


data : DataSource.DataSource Data
data =
    DataSource.succeed ()


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
    { body =
        Html.div
            []
            [ Html.nav
                [ Attr.style "display" "flex"
                , Attr.style "justify-content" "space-evenly"
                ]
                [ Route.Index
                    |> Route.link
                        []
                        [ Html.text "Home" ]
                , Route.PokedexNumber_ { pokedexNumber = "0" }
                    |> Route.link
                        []
                        [ Html.text "To 404 page" ]
                ]
            , Html.div
                [ Attr.style "padding" "40px"
                ]
                pageView.body
            ]
    , title = pageView.title
    }
