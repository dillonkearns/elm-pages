module Pages.ProgramConfig exposing (ProgramConfig)

import ApiRoute
import Browser.Navigation
import BuildError exposing (BuildError)
import Bytes exposing (Bytes)
import Bytes.Decode
import Bytes.Encode
import DataSource exposing (DataSource)
import Dict exposing (Dict)
import Form.FormData exposing (FormData)
import Head
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Json.Encode
import PageServerResponse exposing (PageServerResponse)
import Pages.Fetcher
import Pages.Flags
import Pages.FormState
import Pages.Internal.NotFoundReason exposing (NotFoundReason)
import Pages.Internal.Platform.ToJsPayload
import Pages.Internal.ResponseSketch exposing (ResponseSketch)
import Pages.Internal.RoutePattern exposing (RoutePattern)
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.SiteConfig exposing (SiteConfig)
import Pages.Transition
import Path exposing (Path)
import Url exposing (Url)


type alias ProgramConfig userMsg userModel route pageData actionData sharedData effect mappedMsg errorPage =
    { init :
        Pages.Flags.Flags
        -> sharedData
        -> pageData
        -> Maybe actionData
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
    , update : Pages.FormState.PageFormState -> Dict String (Pages.Transition.FetcherState actionData) -> Maybe Pages.Transition.Transition -> sharedData -> pageData -> Maybe Browser.Navigation.Key -> userMsg -> userModel -> ( userModel, effect )
    , subscriptions : route -> Path -> userModel -> Sub userMsg
    , sharedData : DataSource BuildError sharedData
    , data : Decode.Value -> route -> DataSource BuildError (PageServerResponse pageData errorPage)
    , action : Decode.Value -> route -> DataSource BuildError (PageServerResponse actionData errorPage)
    , onActionData : actionData -> Maybe userMsg
    , view :
        Pages.FormState.PageFormState
        -> Dict String (Pages.Transition.FetcherState actionData)
        -> Maybe Pages.Transition.Transition
        ->
            { path : Path
            , route : route
            }
        -> Maybe PageUrl
        -> sharedData
        -> pageData
        -> Maybe actionData
        ->
            { view : userModel -> { title : String, body : List (Html (Pages.Msg.Msg userMsg)) }
            , head : List Head.Tag
            }
    , handleRoute : route -> DataSource BuildError (Maybe NotFoundReason)
    , getStaticRoutes : DataSource BuildError (List route)
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
        (Maybe { indent : Int, newLines : Bool }
         -> Html Never
         -> String
        )
        -> List (ApiRoute.ApiRoute ApiRoute.Response)
    , pathPatterns : List RoutePattern
    , basePath : List String
    , sendPageData : Pages.Internal.Platform.ToJsPayload.NewThingForPort -> Cmd Never
    , byteEncodePageData : pageData -> Bytes.Encode.Encoder
    , byteDecodePageData : route -> Bytes.Decode.Decoder pageData
    , encodeResponse : ResponseSketch pageData actionData sharedData -> Bytes.Encode.Encoder
    , encodeAction : actionData -> Bytes.Encode.Encoder
    , decodeResponse : Bytes.Decode.Decoder (ResponseSketch pageData actionData sharedData)
    , globalHeadTags : Maybe ((Maybe { indent : Int, newLines : Bool } -> Html Never -> String) -> DataSource BuildError (List Head.Tag))
    , cmdToEffect : Cmd userMsg -> effect
    , perform :
        { fetchRouteData :
            { data : Maybe FormData
            , toMsg : Result Http.Error Url -> userMsg
            }
            -> Cmd mappedMsg
        , submit :
            { values : FormData
            , toMsg : Result Http.Error Url -> userMsg
            }
            -> Cmd mappedMsg
        , fromPageMsg : userMsg -> mappedMsg
        , runFetcher : Pages.Fetcher.Fetcher userMsg -> Cmd mappedMsg
        , key : Browser.Navigation.Key
        , setField : { formId : String, name : String, value : String } -> Cmd mappedMsg
        }
        -> effect
        -> Cmd mappedMsg
    , errorStatusCode : errorPage -> Int
    , notFoundPage : errorPage
    , internalError : String -> errorPage
    , errorPageToData : errorPage -> pageData
    , notFoundRoute : route
    }
