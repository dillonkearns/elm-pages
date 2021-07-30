module Pages.ProgramConfig exposing (ProgramConfig)

import ApiRoute
import Browser.Navigation
import DataSource
import Head
import Html exposing (Html)
import Json.Decode as Decode
import Json.Encode
import Pages.Flags
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.RoutePattern exposing (RoutePattern)
import Pages.PageUrl exposing (PageUrl)
import Pages.SiteConfig exposing (SiteConfig)
import Path exposing (Path)
import Url exposing (Url)


type alias ProgramConfig userMsg userModel route siteData pageData sharedData =
    { init :
        Pages.Flags.Flags
        -> sharedData
        -> pageData
        -> Maybe Browser.Navigation.Key
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
        -> ( userModel, Cmd userMsg )
    , update : sharedData -> pageData -> Maybe Browser.Navigation.Key -> userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : route -> Path -> userModel -> Sub userMsg
    , sharedData : DataSource.DataSource sharedData
    , data : route -> DataSource.DataSource pageData
    , view :
        { path : Path
        , route : route
        }
        -> Maybe PageUrl
        -> sharedData
        -> pageData
        ->
            { view : userModel -> { title : String, body : Html userMsg }
            , head : List Head.Tag
            }
    , handleRoute : route -> DataSource.DataSource (Maybe NotFoundReason)
    , getStaticRoutes : DataSource.DataSource (List route)
    , urlToRoute : Url -> route
    , routeToPath : route -> List String
    , site : SiteConfig route siteData
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , onPageChange :
        { protocol : Url.Protocol
        , host : String
        , port_ : Maybe Int
        , path : Path
        , query : Maybe String
        , fragment : Maybe String
        , metadata : route
        }
        -> userMsg
    , apiRoutes :
        (Html Never -> String)
        -> List (ApiRoute.Done ApiRoute.Response)
    , pathPatterns : List RoutePattern
    , basePath : List String
    }
