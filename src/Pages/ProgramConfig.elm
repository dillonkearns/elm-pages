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


type alias ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData =
    { init :
        sharedStaticData
        -> pageStaticData
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
    , update : sharedStaticData -> pageStaticData -> Maybe Browser.Navigation.Key -> userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : route -> PagePath -> userModel -> Sub userMsg
    , sharedStaticData : DataSource.DataSource sharedStaticData
    , staticData : route -> DataSource.DataSource pageStaticData
    , view :
        { path : PagePath
        , frontmatter : route
        }
        -> sharedStaticData
        -> pageStaticData
        ->
            { view : userModel -> { title : String, body : Html userMsg }
            , head : List Head.Tag
            }
    , handleRoute : route -> DataSource.DataSource Bool
    , getStaticRoutes : DataSource.DataSource (List route)
    , urlToRoute : Url -> route
    , routeToPath : route -> List String
    , site : SiteConfig route siteStaticData
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , generateFiles :
        DataSource.DataSource
            (List
                (Result
                    String
                    { path : List String
                    , content : String
                    }
                )
            )
    , onPageChange :
        { path : PagePath
        , query : Maybe String
        , fragment : Maybe String
        , metadata : route
        }
        -> userMsg
    }
