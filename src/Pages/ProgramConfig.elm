module Pages.ProgramConfig exposing (ProgramConfig)

import ApiRoute
import Browser.Navigation
import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import DataSource exposing (DataSource)
import Head
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode
import PageServerResponse exposing (PageServerResponse)
import Pages.Flags
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.Platform.ToJsPayload
import Pages.Internal.ResponseSketch exposing (ResponseSketch)
import Pages.Internal.RoutePattern exposing (RoutePattern)
import Pages.PageUrl exposing (PageUrl)
import Pages.SiteConfig exposing (SiteConfig)
import Path exposing (Path)
import Task exposing (Task)
import Url exposing (Url)


type alias ProgramConfig userMsg userModel route pageData sharedData effect mappedMsg errorPage =
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
        -> ( userModel, effect )
    , update : sharedData -> pageData -> Maybe Browser.Navigation.Key -> userMsg -> userModel -> ( userModel, effect )
    , subscriptions : route -> Path -> userModel -> Sub userMsg
    , sharedData : DataSource sharedData
    , data : route -> DataSource (PageServerResponse pageData errorPage)
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
    , handleRoute : route -> DataSource (Maybe NotFoundReason)
    , getStaticRoutes : DataSource (List route)
    , urlToRoute : Url -> route
    , routeToPath : route -> List String
    , site : Maybe SiteConfig
    , toJsPort : Json.Encode.Value -> Cmd Never
    , fromJsPort : Sub Decode.Value
    , gotBatchSub : Sub Decode.Value
    , hotReloadData : Sub Bytes
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
        -> List (ApiRoute.ApiRoute ApiRoute.Response)
    , pathPatterns : List RoutePattern
    , basePath : List String
    , fetchPageData : Url -> Maybe { contentType : String, body : String } -> Task Http.Error ( Url, ResponseSketch pageData sharedData )
    , sendPageData : Pages.Internal.Platform.ToJsPayload.NewThingForPort -> Cmd Never
    , byteEncodePageData : pageData -> Bytes.Encode.Encoder
    , byteDecodePageData : route -> Bytes.Decode.Decoder pageData
    , encodeResponse : ResponseSketch pageData sharedData -> Bytes.Encode.Encoder
    , decodeResponse : Bytes.Decode.Decoder (ResponseSketch pageData sharedData)
    , globalHeadTags : Maybe (DataSource (List Head.Tag))
    , cmdToEffect : Cmd userMsg -> effect
    , perform : (userMsg -> mappedMsg) -> Browser.Navigation.Key -> effect -> Cmd mappedMsg
    , errorStatusCode : errorPage -> Int
    , notFoundPage : errorPage
    , internalError : String -> errorPage
    , errorPageToData : errorPage -> pageData
    , notFoundRoute : route
    }
