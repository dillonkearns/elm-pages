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
        pageStaticData
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
    , update : pageStaticData -> Maybe Browser.Navigation.Key -> userMsg -> userModel -> ( userModel, Cmd userMsg )
    , subscriptions : route -> PagePath -> userModel -> Sub userMsg
    , sharedStaticData : DataSource.Request sharedStaticData
    , staticData : route -> DataSource.Request pageStaticData
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
    , getStaticRoutes : DataSource.Request (List route)
    , urlToRoute : Url -> route
    , routeToPath : route -> List String
    , site : SiteConfig route siteStaticData
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , generateFiles :
        DataSource.Request
            (List
                (Result
                    String
                    { path : List String
                    , content : String
                    }
                )
            )
    , onPageChange :
        Maybe
            ({ path : PagePath
             , query : Maybe String
             , fragment : Maybe String
             , metadata : route
             }
             -> userMsg
            )
    }
