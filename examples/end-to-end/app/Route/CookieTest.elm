module Route.CookieTest exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Html.Styled exposing (text)
import Pages.PageUrl exposing (PageUrl)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
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


data : RouteParams -> Parser (BackendTask FatalError (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.expectCookie "dark-mode"
            |> Request.map
                (\darkMode ->
                    BackendTask.succeed (Response.render { darkMode = Just darkMode })
                )
        , Request.succeed
            (BackendTask.succeed (Response.render { darkMode = Nothing }))
        ]


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view static sharedModel =
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
