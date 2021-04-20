module SharedTemplate exposing (..)

import Browser.Navigation
import DataSource
import Document exposing (Document)
import Html exposing (Html)
import Pages.PagePath exposing (PagePath)
import Route exposing (Route)


type alias SharedTemplate sharedMsg sharedModel sharedStaticData mappedMsg =
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
        -> ( sharedModel, Cmd sharedMsg )
    , update : sharedMsg -> sharedModel -> ( sharedModel, Cmd sharedMsg )
    , view :
        sharedStaticData
        ->
            { path : PagePath
            , frontmatter : Maybe Route
            }
        -> sharedModel
        -> (sharedMsg -> mappedMsg)
        -> Document mappedMsg
        -> { body : Html mappedMsg, title : String }
    , staticData : DataSource.DataSource sharedStaticData
    , subscriptions : PagePath -> sharedModel -> Sub sharedMsg
    , onPageChange :
        Maybe
            ({ path : PagePath
             , query : Maybe String
             , fragment : Maybe String
             }
             -> sharedMsg
            )
    }
