module SharedTemplate exposing (SharedTemplate)

import BackendTask
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Html exposing (Html)
import Pages.Flags exposing (Flags)
import Pages.PageUrl exposing (PageUrl)
import UrlPath exposing (UrlPath)
import Route exposing (Route)
import View exposing (View)


type alias SharedTemplate msg sharedModel sharedData mappedMsg =
    { init :
        Flags
        ->
            Maybe
                { path :
                    { path : UrlPath
                    , query : Maybe String
                    , fragment : Maybe String
                    }
                , metadata : Maybe Route
                , pageUrl : Maybe PageUrl
                }
        -> ( sharedModel, Effect msg )
    , update : msg -> sharedModel -> ( sharedModel, Effect msg )
    , view :
        sharedData
        ->
            { path : UrlPath
            , route : Maybe Route
            }
        -> sharedModel
        -> (msg -> mappedMsg)
        -> View mappedMsg
        -> { body : List (Html mappedMsg), title : String }
    , data : BackendTask.BackendTask FatalError sharedData
    , subscriptions : UrlPath -> sharedModel -> Sub msg
    , onPageChange :
        Maybe
            ({ path : UrlPath
             , query : Maybe String
             , fragment : Maybe String
             }
             -> msg
            )
    }
