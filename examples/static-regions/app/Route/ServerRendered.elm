module Route.ServerRendered exposing (ActionData, Data, Model, Msg, route)

{-| Test route for static regions with server-rendered routes.

This route demonstrates that static regions work correctly with server-rendered routes:

1.  Static regions are rendered on each request (not just at build time)
2.  The server bundle includes all the static rendering code
3.  The client bundle excludes the static rendering code (DCE works)
4.  SPA navigation loads static regions from content.dat correctly

-}

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr
import Html.Styled.Events exposing (onClick)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { counter : Int
    }


type Msg
    = Increment
    | Decrement


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias Data =
    { userAgent : String
    , requestTime : String
    }


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = \_ _ -> BackendTask.fail (FatalError.fromString "No actions")
        }
        |> RouteBuilder.buildWithLocalState
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }


{-| Server-rendered data function - receives the request on each request.
-}
data : RouteParams -> Request -> BackendTask FatalError (Response.Response Data errorPage)
data _ request =
    let
        userAgent =
            Request.header "user-agent" request
                |> Maybe.withDefault "Unknown"
    in
    BackendTask.succeed
        (Response.render
            { userAgent = userAgent
            , requestTime = "Server render time"
            }
        )


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init _ _ =
    ( { counter = 0 }, Effect.none )


update : App Data ActionData RouteParams -> Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update _ _ msg model =
    case msg of
        Increment ->
            ( { model | counter = model.counter + 1 }, Effect.none )

        Decrement ->
            ( { model | counter = model.counter - 1 }, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions _ _ _ _ =
    Sub.none


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app _ model =
    { title = "Server-Rendered Static Regions"
    , body =
        [ Html.div [ Attr.style "max-width" "800px", Attr.style "margin" "0 auto", Attr.style "padding" "20px" ]
            [ Html.h1 [] [ Html.text "Server-Rendered Route with Static Regions" ]
            , Html.p []
                [ Html.text "This page is server-rendered (not pre-built). "
                , Html.text "Static regions should still work correctly."
                ]

            -- Request info (dynamic per-request)
            , Html.div
                [ Attr.style "padding" "15px"
                , Attr.style "background" "#fff3cd"
                , Attr.style "border-radius" "8px"
                , Attr.style "margin" "20px 0"
                ]
                [ Html.h3 [ Attr.style "margin-top" "0" ] [ Html.text "Request Info (Dynamic)" ]
                , Html.p [] [ Html.text ("User-Agent: " ++ app.data.userAgent) ]
                , Html.p [] [ Html.text ("Request Time: " ++ app.data.requestTime) ]
                ]

            -- Frozen view - rendered on server, adopted by client
            , View.freeze
                (Html.div
                    [ Attr.style "padding" "20px"
                    , Attr.style "background" "#f0f0ff"
                    , Attr.style "border-radius" "8px"
                    , Attr.style "margin" "20px 0"
                    , Attr.style "border-left" "4px solid #6060ff"
                    ]
                    [ Html.h3 [ Attr.style "margin-top" "0" ] [ Html.text "Frozen View (Server-Rendered)" ]
                    , Html.p [] [ Html.text "This content is rendered on the server per-request." ]
                    , Html.ul []
                        [ Html.li [] [ Html.text "Server-rendered item 1" ]
                        , Html.li [] [ Html.text "Server-rendered item 2" ]
                        , Html.li [] [ Html.text "Heavy processing result" ]
                        ]
                    , Html.p [ Attr.style "font-size" "12px", Attr.style "color" "#666" ]
                        [ Html.text "The rendering code is eliminated from the client bundle via DCE." ]
                    ]
                )

            -- Simple frozen view
            , View.freeze simpleStaticContent

            -- Dynamic counter
            , Html.div
                [ Attr.style "padding" "20px"
                , Attr.style "background" "#e0f0e0"
                , Attr.style "border-radius" "8px"
                , Attr.style "margin" "20px 0"
                ]
                [ Html.h3 [ Attr.style "margin-top" "0" ] [ Html.text "Dynamic Counter" ]
                , Html.p [] [ Html.text ("Counter: " ++ String.fromInt model.counter) ]
                , Html.button
                    [ onClick (PagesMsg.fromMsg Decrement)
                    , Attr.style "margin-right" "10px"
                    , Attr.style "padding" "8px 16px"
                    ]
                    [ Html.text "-" ]
                , Html.button
                    [ onClick (PagesMsg.fromMsg Increment)
                    , Attr.style "padding" "8px 16px"
                    ]
                    [ Html.text "+" ]
                ]

            -- Navigation links
            , Html.div [ Attr.style "margin-top" "20px" ]
                [ Html.h3 [] [ Html.text "Navigation" ]
                , Html.ul []
                    [ Html.li [] [ Html.a [ Attr.href "/" ] [ Html.text "Index" ] ]
                    , Html.li [] [ Html.a [ Attr.href "/static-region-test" ] [ Html.text "Static Region Test (pre-rendered)" ] ]
                    ]
                ]
            ]
        ]
    }


{-| Simple static content - eliminated from client bundle via DCE.
-}
simpleStaticContent : Html Never
simpleStaticContent =
    Html.div
        [ Attr.style "padding" "20px"
        , Attr.style "background" "#f0f0f0"
        , Attr.style "border-radius" "8px"
        , Attr.style "margin" "20px 0"
        ]
        [ Html.h3 [ Attr.style "margin-top" "0" ] [ Html.text "Simple Static Content" ]
        , Html.p [] [ Html.text "This is a simple frozen view." ]
        , Html.p [] [ Html.text "It's rendered on the server and adopted by the client." ]
        ]
