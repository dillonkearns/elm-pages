module Pages.ProgramConfig exposing (..)

import Browser.Navigation
import DataSource
import Head
import Html exposing (Html)
import Json.Decode as Decode
import Json.Encode
import Pages.PagePath exposing (PagePath)
import Pages.SiteConfig exposing (SiteConfig)
import Url exposing (Url)


type alias ProgramConfig userMsg userModel route siteData pageData sharedData =
    { init :
        sharedData
        -> pageData
        -> Maybe Browser.Navigation.Key
        ->
            Maybe
                { path :
                    { path : PagePath
                    , query : Maybe String
                    , fragment : Maybe String
                    }
                , metadata : route
                }
        -> ( userModel, Cmd userMsg )
    , update : sharedData -> pageData -> Maybe Browser.Navigation.Key -> userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : route -> PagePath -> userModel -> Sub userMsg
    , sharedData : DataSource.DataSource sharedData
    , data : route -> DataSource.DataSource pageData
    , view :
        { path : PagePath
        , frontmatter : route
        }
        -> sharedData
        -> pageData
        ->
            { view : userModel -> { title : String, body : Html userMsg }
            , head : List Head.Tag
            }
    , handleRoute : route -> DataSource.DataSource Bool
    , getStaticRoutes : DataSource.DataSource (List route)
    , urlToRoute : Url -> route
    , routeToPath : route -> List String
    , site : SiteConfig route siteData
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , onPageChange :
        { path : PagePath
        , query : Maybe String
        , fragment : Maybe String
        , metadata : route
        }
        -> userMsg
    }
