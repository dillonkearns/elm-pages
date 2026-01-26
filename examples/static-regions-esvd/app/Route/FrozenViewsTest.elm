module Route.FrozenViewsTest exposing (ActionData, Data, Model, Msg, route)

{-| Test route demonstrating the new frozen views pattern with `View.freeze`.

This route demonstrates:

1.  A single Data type that contains both persistent and ephemeral fields
2.  Using View.freeze to mark heavy content for build-time rendering
3.  Ephemeral fields (used only in freeze) are automatically DCE'd
4.  Dynamic content updating normally alongside frozen views

The key insight: fields accessed only inside View.freeze are automatically
detected and removed from the client-side Data type, enabling DCE.

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


{-| Data type with both persistent and ephemeral fields.

  - `timestamp`: Used outside freeze (persistent, sent to client)
  - `markdownContent`, `codeExample`, `sidebarItems`: Used only in freeze (ephemeral, DCE'd)

The elm-review codemod automatically detects which fields are ephemeral
and removes them from the client-side Data type.

-}
type alias Data =
    { timestamp : String
    , markdownContent : String
    , codeExample : String
    , sidebarItems : List String
    }


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


data : BackendTask FatalError Data
data =
    BackendTask.succeed
        { timestamp = "Build time: 2024-01-01T00:00:00Z"
        , markdownContent = """
# Welcome to Frozen Views

This content was **rendered at build time** and is adopted by the client.

The rendering code is eliminated from the client bundle through DCE.

## Benefits

- Smaller client bundles
- No re-rendering on hydration
- Heavy dependencies stay on the server
"""
        , codeExample = """
view app shared model =
    { body =
        [ h1 [] [ text app.data.title ]           -- Persistent
        , View.freeze (render app.data.content)   -- Ephemeral, DCE'd
        ]
    }
"""
        , sidebarItems =
            [ "Getting Started"
            , "API Reference"
            , "Examples"
            , "FAQ"
            ]
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


{-| Render the header - uses ephemeral data, will be DCE'd from client.
-}
renderHeader : Html Never
renderHeader =
    Html.header
        [ Attr.style "padding" "20px"
        , Attr.style "background" "linear-gradient(135deg, #667eea 0%, #764ba2 100%)"
        , Attr.style "color" "white"
        , Attr.style "border-radius" "8px"
        , Attr.style "margin-bottom" "20px"
        ]
        [ Html.h1 [ Attr.style "margin" "0" ]
            [ Html.text "Frozen Views Demo" ]
        , Html.p [ Attr.style "margin" "10px 0 0 0", Attr.style "opacity" "0.9" ]
            [ Html.text "Pre-rendered content with zero client-side overhead" ]
        ]


{-| Render the main content - simulating markdown rendering.
Uses ephemeral data fields (markdownContent, codeExample).
-}
renderContent : Data -> Html Never
renderContent appData =
    Html.div
        [ Attr.style "padding" "20px"
        , Attr.style "background" "#f8f9fa"
        , Attr.style "border-radius" "8px"
        , Attr.style "margin-bottom" "20px"
        ]
        [ Html.h2 [ Attr.style "color" "#333", Attr.style "margin-top" "0" ]
            [ Html.text "Frozen Content" ]
        , Html.p []
            [ Html.text "This simulates rendered markdown content:" ]
        , Html.pre
            [ Attr.style "background" "#e9ecef"
            , Attr.style "padding" "15px"
            , Attr.style "border-radius" "4px"
            , Attr.style "overflow-x" "auto"
            , Attr.style "font-size" "14px"
            ]
            [ Html.code [] [ Html.text appData.markdownContent ] ]
        , Html.h3 [] [ Html.text "Code Example" ]
        , Html.pre
            [ Attr.style "background" "#2d3748"
            , Attr.style "color" "#e2e8f0"
            , Attr.style "padding" "15px"
            , Attr.style "border-radius" "4px"
            , Attr.style "overflow-x" "auto"
            , Attr.style "font-size" "13px"
            ]
            [ Html.code [] [ Html.text appData.codeExample ] ]
        ]


{-| Render the sidebar with navigation items.
Uses ephemeral data field (sidebarItems).
-}
renderSidebar : Data -> Html Never
renderSidebar appData =
    Html.aside
        [ Attr.style "padding" "20px"
        , Attr.style "background" "#fff"
        , Attr.style "border" "1px solid #e2e8f0"
        , Attr.style "border-radius" "8px"
        , Attr.style "margin-bottom" "20px"
        ]
        [ Html.h3 [ Attr.style "margin-top" "0", Attr.style "color" "#4a5568" ]
            [ Html.text "Navigation" ]
        , Html.ul [ Attr.style "list-style" "none", Attr.style "padding" "0", Attr.style "margin" "0" ]
            (appData.sidebarItems
                |> List.map
                    (\item ->
                        Html.li
                            [ Attr.style "padding" "8px 0"
                            , Attr.style "border-bottom" "1px solid #e2e8f0"
                            ]
                            [ Html.a
                                [ Attr.href "#"
                                , Attr.style "color" "#667eea"
                                , Attr.style "text-decoration" "none"
                                ]
                                [ Html.text item ]
                            ]
                    )
            )
        ]


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app _ model =
    { title = "Frozen Views Test"
    , body =
        [ Html.div
            [ Attr.style "max-width" "900px"
            , Attr.style "margin" "0 auto"
            , Attr.style "padding" "20px"
            ]
            [ -- Frozen header - pre-rendered, just embed it
              -- This doesn't use app.data, so the function itself gets DCE'd
              View.freeze renderHeader

            -- Layout with sidebar and content
            , Html.div
                [ Attr.style "display" "grid"
                , Attr.style "grid-template-columns" "250px 1fr"
                , Attr.style "gap" "20px"
                ]
                [ -- Frozen sidebar - uses app.data.sidebarItems (ephemeral)
                  View.freeze (renderSidebar app.data)

                -- Main content area
                , Html.div []
                    [ -- Frozen content - uses app.data.markdownContent and app.data.codeExample (ephemeral)
                      View.freeze (renderContent app.data)

                    -- Dynamic counter - this updates normally
                    , Html.div
                        [ Attr.style "padding" "20px"
                        , Attr.style "background" "#e6fffa"
                        , Attr.style "border-radius" "8px"
                        , Attr.style "border-left" "4px solid #38b2ac"
                        ]
                        [ Html.h3 [ Attr.style "color" "#234e52", Attr.style "margin-top" "0" ]
                            [ Html.text "Dynamic Content" ]
                        , Html.p []
                            [ Html.text ("Counter: " ++ String.fromInt model.counter) ]
                        , Html.button
                            [ onClick (PagesMsg.fromMsg Decrement)
                            , Attr.style "margin-right" "10px"
                            , Attr.style "padding" "8px 16px"
                            , Attr.style "border" "none"
                            , Attr.style "background" "#38b2ac"
                            , Attr.style "color" "white"
                            , Attr.style "border-radius" "4px"
                            , Attr.style "cursor" "pointer"
                            ]
                            [ Html.text "-" ]
                        , Html.button
                            [ onClick (PagesMsg.fromMsg Increment)
                            , Attr.style "padding" "8px 16px"
                            , Attr.style "border" "none"
                            , Attr.style "background" "#38b2ac"
                            , Attr.style "color" "white"
                            , Attr.style "border-radius" "4px"
                            , Attr.style "cursor" "pointer"
                            ]
                            [ Html.text "+" ]
                        , Html.p [ Attr.style "margin-top" "10px", Attr.style "color" "#285e61", Attr.style "font-size" "14px" ]
                            [ Html.text "This counter is interactive and updates normally." ]
                        ]
                    ]
                ]

            -- Navigation links
            , Html.div [ Attr.style "margin-top" "20px" ]
                [ Html.a [ Attr.href "/" ] [ Html.text "← Back to Index" ]
                , Html.text " | "
                , Html.a [ Attr.href "/static-region-test" ] [ Html.text "Static Region Test" ]
                ]

            -- Debug info - uses app.data.timestamp (persistent, used outside freeze)
            , Html.div
                [ Attr.style "margin-top" "20px"
                , Attr.style "padding" "10px"
                , Attr.style "background" "#fffbeb"
                , Attr.style "border-radius" "4px"
                , Attr.style "font-size" "12px"
                , Attr.style "color" "#92400e"
                ]
                [ Html.strong [] [ Html.text "Build timestamp: " ]
                , Html.text app.data.timestamp
                ]
            ]
        ]
    }
