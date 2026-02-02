module Route.StaticRegionTest exposing (ActionData, Data, Model, Msg, StaticData, route)

{-| Test route for static region adoption.

This route demonstrates:

1.  Pre-rendered static HTML being adopted on initial page load
2.  SPA navigation working with HTML from content.dat
3.  Dynamic content updating normally alongside static regions

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


type alias StaticData =
    ()


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildWithLocalState
            { init = init
            , update = update
            , view = view
            , subscriptions = subscriptions
            }


type alias Data =
    { timestamp : String
    }


data : BackendTask FatalError Data
data =
    -- No more staticHtml in Data - it's automatically extracted from rendered output!
    BackendTask.succeed
        { timestamp = "Build time: 2024-01-01T00:00:00Z"
        }


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
    { title = "Static Region Test"
    , body =
        [ Html.div [ Attr.css [], Attr.style "max-width" "800px", Attr.style "margin" "0 auto", Attr.style "padding" "20px" ]
            [ Html.h1 [] [ Html.text "Static Region Adoption Test" ]
            , Html.p []
                [ Html.text "This page tests the static region adoption feature. "
                , Html.text "The gray box below should be adopted from pre-rendered HTML."
                ]

            -- Static region using View.freeze
            -- Server: renders staticContent with data-static wrapper
            -- Client: transforms to lazy thunk for DOM adoption
            -- SPA nav: HTML comes from content.dat
            , View.freeze (staticContent ())

            -- Dynamic region - this updates normally
            , Html.div
                [ Attr.style "padding" "20px"
                , Attr.style "background" "#e0f0e0"
                , Attr.style "border-radius" "8px"
                , Attr.style "margin" "20px 0"
                ]
                [ Html.h2 [ Attr.style "color" "#333", Attr.style "margin-top" "0" ]
                    [ Html.text "Dynamic Content (Normal)" ]
                , Html.p []
                    [ Html.text ("Counter: " ++ String.fromInt model.counter) ]
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
                , Html.p [ Attr.style "margin-top" "10px", Attr.style "color" "#666" ]
                    [ Html.text "This counter is interactive and updates via the normal Elm update cycle." ]
                ]

            -- Link to test SPA navigation
            , Html.div [ Attr.style "margin-top" "20px" ]
                [ Html.h3 [] [ Html.text "SPA Navigation Test" ]
                , Html.p []
                    [ Html.text "Navigate to the "
                    , Html.a [ Attr.href "/" ] [ Html.text "index page" ]
                    , Html.text " and back to test SPA navigation (HTML string parsing)."
                    ]
                ]

            -- Debug info
            , Html.div
                [ Attr.style "margin-top" "20px"
                , Attr.style "padding" "10px"
                , Attr.style "background" "#fff3cd"
                , Attr.style "border-radius" "4px"
                , Attr.style "font-size" "12px"
                ]
                [ Html.strong [] [ Html.text "Debug Info: " ]
                , Html.text app.data.timestamp
                ]
            ]
        ]
    }


{-| Static content rendered on the server.

This function is called during server-side rendering but is dead-code eliminated
in the client bundle after the elm-review transformation converts
`View.freeze` to a lazy thunk.

In a real application, this could include:

  - Markdown rendering
  - Syntax highlighting
  - Complex data transformations
  - Heavy dependencies that shouldn't be in the client bundle

-}
staticContent : () -> Html Never
staticContent () =
    Html.div
        [ Attr.style "padding" "20px"
        , Attr.style "background" "#f0f0f0"
        , Attr.style "border-radius" "8px"
        , Attr.style "margin" "20px 0"
        ]
        [ Html.h2
            [ Attr.style "color" "#333"
            , Attr.style "margin-top" "0"
            ]
            [ Html.text "Static Content (Server Rendered)" ]
        , Html.p []
            [ Html.text "This content was rendered at build time using View.freeze." ]
        , Html.p []
            [ Html.text "If you see this without a flash, adoption worked!" ]
        , Html.ul []
            [ Html.li [] [ Html.text "Item 1 - rendered on server" ]
            , Html.li [] [ Html.text "Item 2 - adopted by virtual-dom" ]
            , Html.li [] [ Html.text "Item 3 - never re-rendered on client" ]
            ]
        , Html.p []
            [ Html.em []
                [ Html.text "In production, this could be markdown, syntax-highlighted code, etc." ]
            ]
        ]
