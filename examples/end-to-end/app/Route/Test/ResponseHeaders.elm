module Route.Test.ResponseHeaders exposing (ActionData, Data, Model, Msg, route)

import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import DataSource.File
import ErrorPage exposing (ErrorPage)
import Exception exposing (Throwable)
import Head
import Html.Styled exposing (div, text)
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request exposing (Parser)
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


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ -> Request.skip ""
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { greeting : String
    }


data : RouteParams -> Parser (DataSource Throwable (Response Data ErrorPage))
data routeParams =
    Request.succeed
        (DataSource.succeed Data
            |> DataSource.andMap (DataSource.File.rawFile "greeting.txt" |> DataSource.throw)
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
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "Response Headers Test"
    , body =
        [ text "Response Headers Test"
        , div []
            [ text static.data.greeting
            ]
        ]
    }
