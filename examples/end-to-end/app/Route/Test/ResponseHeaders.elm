module Route.Test.ResponseHeaders exposing (Data, Model, Msg, route)

import Base64
import DataSource exposing (DataSource)
import DataSource.File
import Head
import Html.Styled exposing (div, text)
import Pages.PageUrl exposing (PageUrl)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    }


data : RouteParams -> Request (DataSource (Response Data))
data routeParams =
    Request.succeed
        (DataSource.succeed Data
            |> DataSource.andMap (DataSource.File.rawFile "greeting.txt")
            |> DataSource.map Response.render
            |> DataSource.map (Response.withHeader "x-powered-by" "my-framework")
        )



--Request.oneOf
--    [ Request.expectHeader "if-none-match"
--        |> Request.andThen
--            (\ifNoneMatch ->
--                if ifNoneMatch == "v3" then
--                    DataSource.succeed
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
--        (DataSource.succeed Data
--            |> DataSource.andMap (DataSource.File.rawFile "greeting.txt")
--            |> DataSource.map Response.render
--            |> DataSource.map (Response.withHeader "ETag" "v3")
--        )
--    , Request.succeed
--        (DataSource.succeed
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
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Msg
view maybeUrl sharedModel static =
    { title = "Response Headers Test"
    , body =
        [ text "Response Headers Test"
        , div []
            [ text static.data.greeting
            ]
        ]
    }
