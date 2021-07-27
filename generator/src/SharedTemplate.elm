module SharedTemplate exposing (SharedTemplate)

import Browser.Navigation
import DataSource
import Html exposing (Html)
import Pages.Flags exposing (Flags)
import Pages.PageUrl exposing (PageUrl)
import Path exposing (Path)
import Route exposing (Route)
import View exposing (View)


type alias SharedTemplate msg sharedModel sharedData mappedMsg =
    { init :
        Maybe Browser.Navigation.Key
        -> Flags
        ->
            Maybe
                { path :
                    { path : Path
                    , query : Maybe String
                    , fragment : Maybe String
                    }
                , metadata : Maybe Route
                , pageUrl : Maybe PageUrl
                }
        -> ( sharedModel, Cmd msg )
    , update : msg -> sharedModel -> ( sharedModel, Cmd msg )
    , view :
        sharedData
        ->
            { path : Path
            , route : Maybe Route
            }
        -> sharedModel
        -> (msg -> mappedMsg)
        -> View mappedMsg
        -> { body : Html mappedMsg, title : String }
    , data : DataSource.DataSource sharedData
    , subscriptions : Path -> sharedModel -> Sub msg
    , onPageChange :
        Maybe
            ({ path : Path
             , query : Maybe String
             , fragment : Maybe String
             }
             -> msg
            )
    }
