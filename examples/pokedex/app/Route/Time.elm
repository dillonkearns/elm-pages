module Route.Time exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Dict exposing (Dict)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html
import PagesMsg exposing (PagesMsg)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import Url
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip "No action."
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Request =
    { language : Maybe String
    , method : Request.Method
    , queryParams : Dict String (List String)
    , protocol : Url.Protocol
    , allHeaders : Dict String String
    }



--data : ServerRequest.IsAvailable -> RouteParams -> BackendTask (PageServerResponse Data)
--data serverRequestKey routeParams =
--    let
--        serverReq : ServerRequest Request
--        serverReq =
--            ServerRequest.init
--                (\language method queryParams protocol allHeaders ->
--                    { language = language
--                    , method = method
--                    , queryParams = queryParams |> QueryParams.toDict
--                    , protocol = protocol
--                    , allHeaders = allHeaders
--                    }
--                )
--                |> ServerRequest.optionalHeader "accept-language"
--                |> ServerRequest.withMethod
--                |> ServerRequest.withQueryParams
--                |> ServerRequest.withProtocol
--                |> ServerRequest.withAllHeaders
--    in
--    serverReq
--        |> ServerRequest.toBackendTask serverRequestKey
--        |> BackendTask.andThen
--            (\req ->
--                case req.queryParams |> Dict.get "redirect" of
--                    Just [ redirectTo ] ->
--                        BackendTask.succeed (PageServerResponse.ServerResponse (ServerResponse.temporaryRedirect redirectTo))
--
--                    Just redirectParams ->
--                        BackendTask.succeed
--                            (PageServerResponse.ServerResponse
--                                (ServerResponse.stringBody
--                                    ("I got the wrong number of redirect query parameters (expected 1):\n"
--                                        ++ (redirectParams |> String.join "\n")
--                                    )
--                                    |> ServerResponse.withStatusCode 400
--                                )
--                            )
--
--                    _ ->
--                        req
--                            |> BackendTask.succeed
--                            |> BackendTask.map Data
--                            |> BackendTask.map PageServerResponse.RenderPage


data : RouteParams -> Request.Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.succeed ()
        |> Request.map
            (\() ->
                Response.plainText "Hello, this is a string"
                    |> BackendTask.succeed
            )


head :
    StaticPayload Data ActionData RouteParams
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


type alias ActionData =
    {}


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (PagesMsg Msg)
view maybeUrl sharedModel static =
    { title = "Time"
    , body =
        [ Html.text
            (static.data.request.language
                |> Maybe.withDefault "No language"
            )
        ]
    }
