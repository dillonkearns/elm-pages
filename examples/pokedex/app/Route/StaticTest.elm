module Route.StaticTest exposing (ActionData, Data, Model, Msg, route)

{-| A test route for StaticOnlyData with serverRendered routes.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Time
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Html
import Html.Attributes as Attr
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import Time
import View exposing (View)
import View.Static


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatelessRoute RouteParams Data () ActionData
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> BackendTask.succeed (Response.render {})
        }
        |> RouteBuilder.buildNoState { view = view }


{-| Static content - rendered at request time, eliminated from client bundle.
Contains the server render time which gets "frozen" in the static HTML.
-}
type alias StaticContent =
    { serverRenderTime : Time.Posix
    , items : List String
    , description : String
    }


type alias Data =
    { requestTime : Time.Posix
    , staticContent : View.Static.StaticOnlyData StaticContent
    }


type alias ActionData =
    {}


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data routeParams request =
    let
        requestTime =
            Request.requestTime request
    in
    BackendTask.map2
        (\staticContent _ ->
            { requestTime = requestTime
            , staticContent = staticContent
            }
                |> Response.render
        )
        -- Use View.Static.backendTask to wrap data fetched via BackendTask
        -- This is the idiomatic pattern - the BackendTask is eliminated from client
        (View.Static.backendTask
            (BackendTask.Time.now
                |> BackendTask.map
                    (\now ->
                        { serverRenderTime = now
                        , items = [ "Item 1", "Item 2", "Item 3", "Item 4", "Item 5" ]
                        , description = "This content is rendered as a static region. The render function and data are eliminated from the client bundle."
                        }
                    )
            )
        )
        -- Dummy task to make the types work (we already have requestTime from Request)
        (BackendTask.succeed ())


head : App Data () ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Static Test"
    , body =
        [ Html.main_ [ Attr.style "max-width" "800px", Attr.style "margin" "0 auto", Attr.style "padding" "20px" ]
            [ Html.h1 [] [ Html.text "StaticOnlyData Test (Server Rendered)" ]
            , Html.p []
                [ Html.text "Request time (dynamic): "
                , Html.text (String.fromInt (Time.posixToMillis app.data.requestTime))
                ]
            , Html.hr [] []
            , Html.h2 [] [ Html.text "Static Region Below:" ]
            , View.staticView app.data.staticContent renderStaticContent
            ]
        ]
    }


{-| Render the static content.
This code is eliminated from the client bundle via DCE.
-}
renderStaticContent : StaticContent -> View.Static
renderStaticContent content =
    Html.div [ Attr.style "background-color" "#f0f0f0", Attr.style "padding" "20px", Attr.style "border-radius" "8px" ]
        [ Html.p []
            [ Html.strong [] [ Html.text "Server render time (static): " ]
            , Html.text (String.fromInt (Time.posixToMillis content.serverRenderTime))
            ]
        , Html.p [] [ Html.text content.description ]
        , Html.ul []
            (List.map
                (\item -> Html.li [] [ Html.text item ])
                content.items
            )
        ]
