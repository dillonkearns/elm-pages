module Shared exposing (Data, Model, Msg(..), SharedMsg(..), template)

import Browser.Navigation
import BackendTask
import Html exposing (Html)
import Html.Events
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
    , onPageChange = Nothing
    }


type Msg
    = SharedMsg SharedMsg
    | MenuClicked


type alias Data =
    ()


type SharedMsg
    = NoOp


type alias Model =
    { showMenu : Bool
    }


init :
    Maybe Browser.Navigation.Key
    -> Pages.Flags.Flags
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
    -> ( Model, Cmd Msg )
init navigationKey flags maybePagePath =
    ( { showMenu = False }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SharedMsg globalMsg ->
            ( model, Cmd.none )

        MenuClicked ->
            ( { model | showMenu = not model.showMenu }, Cmd.none )


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
    { body =
        Html.div []
            [ Html.nav []
                [ Html.button
                    [ Html.Events.onClick MenuClicked ]
                    [ Html.text
                        (if model.showMenu then
                            "Close Menu"

                         else
                            "Open Menu"
                        )
                    ]
                , if model.showMenu then
                    Html.ul []
                        [ Html.li [] [ Html.text "Menu item 1" ]
                        , Html.li [] [ Html.text "Menu item 2" ]
                        ]

                  else
                    Html.text ""
                ]
                |> Html.map toMsg
            , Html.main_ [] pageView.body
            ]
    , title = pageView.title
    }
