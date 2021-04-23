module SharedTemplate exposing (..)

import Browser.Navigation
import DataSource
import Document exposing (Document)
import Html exposing (Html)
import Pages.PagePath exposing (PagePath)
import Route exposing (Route)


type alias SharedTemplate msg sharedModel sharedData sharedMsg mappedMsg =
    { init :
        Maybe Browser.Navigation.Key
        ->
            Maybe
                { path :
                    { path : PagePath
                    , query : Maybe String
                    , fragment : Maybe String
                    }
                , metadata : Maybe Route
                }
        -> ( sharedModel, Cmd msg )
    , update : msg -> sharedModel -> ( sharedModel, Cmd msg )
    , view :
        sharedData
        ->
            { path : PagePath
            , frontmatter : Maybe Route
            }
        -> sharedModel
        -> (msg -> mappedMsg)
        -> Document mappedMsg
        -> { body : Html mappedMsg, title : String }
    , data : DataSource.DataSource sharedData
    , subscriptions : PagePath -> sharedModel -> Sub msg
    , onPageChange :
        Maybe
            ({ path : PagePath
             , query : Maybe String
             , fragment : Maybe String
             }
             -> msg
            )
    , sharedMsg : sharedMsg -> msg
    }
