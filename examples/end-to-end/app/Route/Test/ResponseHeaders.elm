module Route.Test.ResponseHeaders exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import BackendTask.File
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Html.Styled exposing (div, text)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Server.Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> "No actions" |> FatalError.fromString |> BackendTask.fail
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    }


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    BackendTask.succeed Data
        |> BackendTask.andMap (BackendTask.File.rawFile "greeting.txt" |> BackendTask.allowFatal)
        |> BackendTask.map Response.render
        |> BackendTask.map (Response.withHeader "x-powered-by" "my-framework")



--Request.oneOf
--    [ Request.expectHeader "if-none-match"
--        |> Request.andThen
--            (\ifNoneMatch ->
--                if ifNoneMatch == "v3" then
--                    BackendTask.succeed
--                        (Response.customResponse
--                            { statusCode = 304
--                            , headers = []
--                            , body = Nothing
--                            , isBase64Encoded = False
--                            }
--                        )
--                        |> Request.succeed
--
--                else
--                    Request.skipMatch (Request.validationError "")
--            )
--    , Request.succeed
--        (BackendTask.succeed Data
--            |> BackendTask.andMap (BackendTask.File.rawFile "greeting.txt")
--            |> BackendTask.map Response.render
--            |> BackendTask.map (Response.withHeader "ETag" "v3")
--        )
--    , Request.succeed
--        (BackendTask.succeed
--            (Response.customResponse
--                { statusCode = 304
--                , headers = []
--                , body = Nothing
--                , isBase64Encoded = False
--                }
--            )
--        )
--    ]


head :
    App Data () ActionData RouteParams
    -> List Head.Tag
head app =
    []


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Response Headers Test"
    , body =
        [ text "Response Headers Test"
        , div []
            [ text app.data.greeting
            ]
        ]
    }
