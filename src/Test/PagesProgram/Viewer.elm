module Test.PagesProgram.Viewer exposing (app, Flags, Model, Msg)

{-| A browser-based visual test runner that lets you step through elm-pages
test snapshots in your browser. Displays the rendered page view at each step,
with a timeline of events and optional model inspector.

    module TestViewer exposing (main)

    import Test.PagesProgram as PagesProgram
    import Test.PagesProgram.Viewer as Viewer

    main =
        Viewer.app
            [ ( "Blog loads posts"
              , myBlogTest |> PagesProgram.toSnapshots
              )
            , ( "Counter increments"
              , myCounterTest |> PagesProgram.toSnapshots
              )
            ]

Open the compiled HTML in your browser, then use arrow keys to step through.

@docs app, Flags, Model, Msg

-}

import Browser
import Browser.Events
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events
import Json.Decode as Decode
import Test.PagesProgram exposing (Snapshot)


{-| Flags for the viewer app. Currently unused.
-}
type alias Flags =
    ()


{-| The viewer's model.
-}
type alias Model =
    { tests : List NamedTest
    , currentTestIndex : Int
    , currentStepIndex : Int
    , showModel : Bool
    }


type alias NamedTest =
    { name : String
    , snapshots : List Snapshot
    }


{-| The viewer's messages.
-}
type Msg
    = NextStep
    | PrevStep
    | GoToStep Int
    | NextTest
    | PrevTest
    | GoToTest Int
    | ToggleModel
    | KeyDown String
    | NoOp


{-| Create a visual test runner application. Pass a list of named tests with
their snapshots.

    main =
        Viewer.app
            [ ( "my test", myTest |> PagesProgram.toSnapshots )
            ]

-}
app : List ( String, List Snapshot ) -> Program Flags Model Msg
app tests =
    Browser.document
        { init =
            \_ ->
                ( { tests =
                        tests
                            |> List.map
                                (\( name, snapshots ) ->
                                    { name = name, snapshots = snapshots }
                                )
                  , currentTestIndex = 0
                  , currentStepIndex = 0
                  , showModel = False
                  }
                , Cmd.none
                )
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onKeyDown
        (Decode.field "key" Decode.string
            |> Decode.map KeyDown
        )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NextStep ->
            ( { model
                | currentStepIndex =
                    min (currentSnapshotCount model - 1) (model.currentStepIndex + 1)
              }
            , Cmd.none
            )

        PrevStep ->
            ( { model | currentStepIndex = max 0 (model.currentStepIndex - 1) }
            , Cmd.none
            )

        GoToStep index ->
            ( { model
                | currentStepIndex =
                    clamp 0 (currentSnapshotCount model - 1) index
              }
            , Cmd.none
            )

        NextTest ->
            if List.length model.tests <= 1 then
                ( model, Cmd.none )

            else
                ( { model
                    | currentTestIndex =
                        modBy (List.length model.tests) (model.currentTestIndex + 1)
                    , currentStepIndex = 0
                  }
                , Cmd.none
                )

        PrevTest ->
            if List.length model.tests <= 1 then
                ( model, Cmd.none )

            else
                ( { model
                    | currentTestIndex =
                        modBy (List.length model.tests) (model.currentTestIndex - 1 + List.length model.tests)
                    , currentStepIndex = 0
                  }
                , Cmd.none
                )

        GoToTest index ->
            ( { model
                | currentTestIndex = clamp 0 (List.length model.tests - 1) index
                , currentStepIndex = 0
              }
            , Cmd.none
            )

        ToggleModel ->
            ( { model | showModel = not model.showModel }, Cmd.none )

        KeyDown key ->
            case key of
                "ArrowRight" ->
                    update NextStep model

                "ArrowLeft" ->
                    update PrevStep model

                "ArrowDown" ->
                    update NextTest model

                "ArrowUp" ->
                    update PrevTest model

                "m" ->
                    update ToggleModel model

                _ ->
                    ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


currentSnapshotCount : Model -> Int
currentSnapshotCount model =
    model.tests
        |> List.drop model.currentTestIndex
        |> List.head
        |> Maybe.map (.snapshots >> List.length)
        |> Maybe.withDefault 0


currentSnapshot : Model -> Maybe Snapshot
currentSnapshot model =
    model.tests
        |> List.drop model.currentTestIndex
        |> List.head
        |> Maybe.andThen
            (\test ->
                test.snapshots
                    |> List.drop model.currentStepIndex
                    |> List.head
            )


currentTestName : Model -> String
currentTestName model =
    model.tests
        |> List.drop model.currentTestIndex
        |> List.head
        |> Maybe.map .name
        |> Maybe.withDefault ""


view : Model -> Browser.Document Msg
view model =
    { title = "elm-pages Test Viewer"
    , body =
        [ Html.node "style" [] [ Html.text css ]
        , Html.div [ Attr.class "viewer" ]
            [ viewHeader model
            , case currentSnapshot model of
                Just snapshot ->
                    Html.div [ Attr.class "viewer-content" ]
                        [ viewRenderedPage snapshot
                        , viewTimeline model
                        , if model.showModel then
                            viewModelInspector snapshot

                          else
                            Html.text ""
                        ]

                Nothing ->
                    Html.div [ Attr.class "viewer-empty" ]
                        [ Html.text "No snapshots to display" ]
            ]
        ]
    }


viewHeader : Model -> Html Msg
viewHeader model =
    Html.div [ Attr.class "viewer-header" ]
        [ Html.div [ Attr.class "header-left" ]
            [ Html.span [ Attr.class "header-logo" ] [ Html.text "elm-pages" ]
            , Html.span [ Attr.class "header-title" ] [ Html.text " Test Viewer" ]
            ]
        , Html.div [ Attr.class "header-center" ]
            [ if List.length model.tests > 1 then
                Html.div [ Attr.class "test-selector" ]
                    (model.tests
                        |> List.indexedMap
                            (\i test ->
                                Html.button
                                    [ Attr.classList
                                        [ ( "test-tab", True )
                                        , ( "test-tab-active", i == model.currentTestIndex )
                                        ]
                                    , Html.Events.onClick (GoToTest i)
                                    ]
                                    [ Html.text test.name ]
                            )
                    )

              else
                Html.span [ Attr.class "test-name" ]
                    [ Html.text (currentTestName model) ]
            ]
        , Html.div [ Attr.class "header-right" ]
            [ Html.span [ Attr.class "step-counter" ]
                [ Html.text
                    ("Step "
                        ++ String.fromInt (model.currentStepIndex + 1)
                        ++ " / "
                        ++ String.fromInt (currentSnapshotCount model)
                    )
                ]
            , Html.button
                [ Attr.class "nav-button"
                , Html.Events.onClick PrevStep
                , Attr.disabled (model.currentStepIndex <= 0)
                ]
                [ Html.text "<" ]
            , Html.button
                [ Attr.class "nav-button"
                , Html.Events.onClick NextStep
                , Attr.disabled (model.currentStepIndex >= currentSnapshotCount model - 1)
                ]
                [ Html.text ">" ]
            , Html.button
                [ Attr.classList
                    [ ( "toggle-button", True )
                    , ( "toggle-active", model.showModel )
                    ]
                , Html.Events.onClick ToggleModel
                ]
                [ Html.text "Model" ]
            ]
        ]


viewRenderedPage : Snapshot -> Html Msg
viewRenderedPage snapshot =
    Html.div [ Attr.class "rendered-page" ]
        [ Html.div [ Attr.class "page-title-bar" ]
            [ Html.text snapshot.title ]
        , Html.div [ Attr.class "page-body" ]
            (snapshot.body
                |> List.map (Html.map (\_ -> NoOp))
            )
        ]


viewTimeline : Model -> Html Msg
viewTimeline model =
    let
        snapshots =
            model.tests
                |> List.drop model.currentTestIndex
                |> List.head
                |> Maybe.map .snapshots
                |> Maybe.withDefault []
    in
    Html.div [ Attr.class "timeline" ]
        [ Html.div [ Attr.class "timeline-label" ] [ Html.text "Timeline" ]
        , Html.div [ Attr.class "timeline-track" ]
            (snapshots
                |> List.indexedMap
                    (\i snapshot ->
                        Html.div
                            [ Attr.classList
                                [ ( "timeline-step", True )
                                , ( "timeline-step-active", i == model.currentStepIndex )
                                , ( "timeline-step-past", i < model.currentStepIndex )
                                , ( "timeline-step-error", snapshot.label == "ERROR" )
                                , ( "timeline-step-pending", snapshot.hasPendingEffects )
                                ]
                            , Html.Events.onClick (GoToStep i)
                            ]
                            [ Html.div [ Attr.class "timeline-dot" ] []
                            , Html.div [ Attr.class "timeline-step-label" ]
                                [ Html.text snapshot.label ]
                            ]
                    )
            )
        ]


viewModelInspector : Snapshot -> Html Msg
viewModelInspector snapshot =
    Html.div [ Attr.class "model-inspector" ]
        [ Html.div [ Attr.class "inspector-header" ] [ Html.text "Model" ]
        , Html.pre [ Attr.class "inspector-body" ]
            [ Html.text
                (snapshot.modelState
                    |> Maybe.withDefault "(use withModelToString to enable)"
                )
            ]
        ]


css : String
css =
    """
* { margin: 0; padding: 0; box-sizing: border-box; }

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #1a1a2e;
    color: #e0e0e0;
    height: 100vh;
    overflow: hidden;
}

.viewer {
    display: flex;
    flex-direction: column;
    height: 100vh;
}

.viewer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 16px;
    background: #16213e;
    border-bottom: 1px solid #0f3460;
    flex-shrink: 0;
}

.header-left {
    display: flex;
    align-items: center;
    gap: 4px;
}

.header-logo {
    color: #4cc9f0;
    font-weight: 700;
    font-size: 14px;
}

.header-title {
    color: #8899aa;
    font-size: 14px;
}

.header-center {
    flex: 1;
    display: flex;
    justify-content: center;
}

.test-selector {
    display: flex;
    gap: 4px;
}

.test-tab {
    padding: 4px 12px;
    border: 1px solid #0f3460;
    background: transparent;
    color: #8899aa;
    border-radius: 4px;
    cursor: pointer;
    font-size: 12px;
}

.test-tab:hover {
    background: #0f3460;
    color: #e0e0e0;
}

.test-tab-active {
    background: #0f3460;
    color: #4cc9f0;
    border-color: #4cc9f0;
}

.test-name {
    color: #4cc9f0;
    font-weight: 600;
    font-size: 14px;
}

.header-right {
    display: flex;
    align-items: center;
    gap: 8px;
}

.step-counter {
    color: #8899aa;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
}

.nav-button {
    width: 28px;
    height: 28px;
    border: 1px solid #0f3460;
    background: transparent;
    color: #4cc9f0;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
    display: flex;
    align-items: center;
    justify-content: center;
}

.nav-button:hover:not(:disabled) {
    background: #0f3460;
}

.nav-button:disabled {
    opacity: 0.3;
    cursor: default;
}

.toggle-button {
    padding: 4px 10px;
    border: 1px solid #0f3460;
    background: transparent;
    color: #8899aa;
    border-radius: 4px;
    cursor: pointer;
    font-size: 12px;
}

.toggle-button:hover {
    background: #0f3460;
    color: #e0e0e0;
}

.toggle-active {
    background: #0f3460;
    color: #4cc9f0;
    border-color: #4cc9f0;
}

.viewer-content {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
}

.rendered-page {
    flex: 1;
    overflow: auto;
    background: #ffffff;
    color: #1a1a1a;
    margin: 12px;
    border-radius: 8px;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.3);
}

.page-title-bar {
    padding: 8px 16px;
    background: #f0f0f0;
    border-bottom: 1px solid #ddd;
    font-size: 12px;
    color: #666;
    border-radius: 8px 8px 0 0;
    display: flex;
    align-items: center;
    gap: 8px;
}

.page-title-bar::before {
    content: "";
    display: inline-flex;
    gap: 6px;
}

.page-body {
    padding: 16px;
}

.timeline {
    flex-shrink: 0;
    padding: 8px 12px 12px;
    background: #16213e;
    border-top: 1px solid #0f3460;
}

.timeline-label {
    font-size: 11px;
    color: #556677;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 8px;
    padding-left: 4px;
}

.timeline-track {
    display: flex;
    gap: 2px;
    overflow-x: auto;
    padding-bottom: 4px;
}

.timeline-step {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 4px 8px;
    border-radius: 4px;
    cursor: pointer;
    min-width: 48px;
    transition: background 0.1s;
}

.timeline-step:hover {
    background: rgba(76, 201, 240, 0.1);
}

.timeline-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: #334455;
    border: 2px solid #556677;
    transition: all 0.15s;
}

.timeline-step-active .timeline-dot {
    background: #4cc9f0;
    border-color: #4cc9f0;
    box-shadow: 0 0 6px rgba(76, 201, 240, 0.5);
}

.timeline-step-past .timeline-dot {
    background: #2a6e4e;
    border-color: #3a8e6e;
}

.timeline-step-error .timeline-dot {
    background: #e74c3c;
    border-color: #e74c3c;
}

.timeline-step-pending .timeline-dot {
    border-style: dashed;
}

.timeline-step-label {
    font-size: 10px;
    color: #556677;
    white-space: nowrap;
    max-width: 80px;
    overflow: hidden;
    text-overflow: ellipsis;
}

.timeline-step-active .timeline-step-label {
    color: #4cc9f0;
    font-weight: 600;
}

.timeline-step-past .timeline-step-label {
    color: #3a8e6e;
}

.model-inspector {
    flex-shrink: 0;
    max-height: 200px;
    overflow: auto;
    background: #0d1117;
    border-top: 1px solid #0f3460;
}

.inspector-header {
    font-size: 11px;
    color: #556677;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    padding: 8px 12px 4px;
}

.inspector-body {
    padding: 4px 12px 12px;
    font-family: "SF Mono", "Fira Code", monospace;
    font-size: 12px;
    color: #7ee787;
    white-space: pre-wrap;
    word-break: break-all;
}

.viewer-empty {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #556677;
    font-size: 16px;
}

/* Keyboard shortcut hint */
.viewer::after {
    content: "← → step   ↑ ↓ test   m model";
    position: fixed;
    bottom: 4px;
    right: 12px;
    font-size: 10px;
    color: #334455;
}
"""
