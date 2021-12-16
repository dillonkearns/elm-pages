module Page.Time exposing (Data, Model, Msg, page)

import DataSource exposing (DataSource)
import DataSource.ServerRequest as ServerRequest exposing (ServerRequest)
import Dict exposing (Dict)
import Head
import Head.Seo as Seo
import Html
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import QueryParams exposing (QueryParams)
import Shared
import Url
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    Never


type alias RouteParams =
    {}


page : Page RouteParams Data
page =
    Page.serverless
        { head = head
        , data = data
        , routeFound = \_ -> DataSource.succeed True
        }
        --{ data : (ServerRequest decodedRequest -> DataSource decodedRequest) -> routeParams -> DataSource data
        --, routeFound : routeParams -> DataSource Bool
        --, head : StaticPayload data routeParams -> List Head.Tag
        --}
        |> Page.buildNoState { view = view }


type alias Request =
    { language : Maybe String
    , method : ServerRequest.Method
    , queryParams : Dict String (List String)
    , protocol : Url.Protocol
    , allHeaders : Dict String String
    }


data : (ServerRequest a -> DataSource a) -> RouteParams -> DataSource Data
data resolveServerRequest routeParams =
    let
        serverReq : ServerRequest Request
        serverReq =
            ServerRequest.init
                (\language method queryParams protocol allHeaders ->
                    { language = language
                    , method = method
                    , queryParams = queryParams |> QueryParams.toDict
                    , protocol = protocol
                    , allHeaders = allHeaders
                    }
                )
                |> ServerRequest.optionalHeader "accept-language"
                |> ServerRequest.withMethod
                |> ServerRequest.withQueryParams
                |> ServerRequest.withProtocol
                |> ServerRequest.withAllHeaders
    in
    serverReq
        |> ServerRequest.toDataSource
        |> DataSource.map Data


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "Time"
        }
        |> Seo.website


type alias Data =
    { request : Request
    }


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Time"
    , body =
        [ Html.text (static.data.request |> Debug.toString)
        ]
    }
