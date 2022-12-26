module Route.CookieTest exposing (ActionData, Data, Model, Msg, route)

import BuildError exposing (BuildError)
import DataSource exposing (DataSource)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Html.Styled exposing (text)
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
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
        , action = \_ -> Request.skip "No action."
        }
        |> RouteBuilder.buildNoState { view = view }


type alias Data =
    { darkMode : Maybe String }


data : RouteParams -> Parser (DataSource BuildError (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.expectCookie "dark-mode"
            |> Request.map
                (\darkMode ->
                    DataSource.succeed (Response.render { darkMode = Just darkMode })
                )
        , Request.succeed
            (DataSource.succeed (Response.render { darkMode = Nothing }))
        ]


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
    { title = "Cookie test"
    , body =
        [ case static.data.darkMode of
            Just darkMode ->
                text <|
                    "Dark mode: "
                        ++ darkMode

            Nothing ->
                text "No dark mode preference set"
        ]
    }
