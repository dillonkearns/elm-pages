module MiniGitTests exposing (suite)

import Ansi.Color
import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Sub
import Tui.Test as TuiTest


suite : Test
suite =
    describe "MiniGit"
        [ describe "keyboard navigation"
            [ test "initial view shows commit list with first selected" <|
                \() ->
                    miniGitTest
                        |> TuiTest.ensureViewHas "▸ abc1234"
                        |> TuiTest.ensureViewHas "  def5678"
                        |> TuiTest.expectRunning
            , test "initial view shows selected commit detail" <|
                \() ->
                    miniGitTest
                        |> TuiTest.ensureViewHas "Initial commit"
                        |> TuiTest.expectRunning
            , test "j moves selection down" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.ensureViewHas "Add feature"
                        |> TuiTest.expectRunning
            , test "k moves selection up" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.ensureViewHas "▸ abc1234"
                        |> TuiTest.expectRunning
            , test "selection doesn't go below last item" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "▸ 789abcd"
                        |> TuiTest.expectRunning
            , test "q exits" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'q'
                        |> TuiTest.expectExit
            ]
        , describe "mouse interactions"
            [ test "clicking on a commit selects it" <|
                \() ->
                    miniGitTest
                        |> TuiTest.click { row = 3, col = 5 }
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.ensureViewHas "Add feature"
                        |> TuiTest.expectRunning
            , test "clicking on third commit selects it" <|
                \() ->
                    miniGitTest
                        |> TuiTest.click { row = 4, col = 5 }
                        |> TuiTest.ensureViewHas "▸ 345cdef"
                        |> TuiTest.ensureViewHas "Fix bug"
                        |> TuiTest.expectRunning
            , test "scroll down moves selection" <|
                \() ->
                    miniGitTest
                        |> TuiTest.scrollDown { row = 3, col = 5 }
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
            , test "scroll up moves selection" <|
                \() ->
                    miniGitTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.scrollUp { row = 3, col = 5 }
                        |> TuiTest.ensureViewHas "▸ def5678"
                        |> TuiTest.expectRunning
            ]
        , describe "scrolling long lists"
            [ test "scrolling past visible area shifts the viewport" <|
                \() ->
                    -- Start with a larger terminal so adjustScroll works
                    TuiTest.startWithContext { width = 80, height = 20 }
                        { data = longCommitList
                        , init = miniGitInit
                        , update = miniGitUpdate
                        , view = miniGitView
                        , subscriptions = miniGitSubscriptions
                        }
                        -- Move down past the 5-row scroll window
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        -- The selected commit (sha0007) should be visible
                        |> TuiTest.ensureViewHas "▸ sha0007"
                        |> TuiTest.expectRunning
            ]
        , describe "snapshots with model inspection"
            [ test "model state shows selection index" <|
                \() ->
                    miniGitTest
                        |> TuiTest.withModelToString Debug.toString
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.toSnapshots
                        |> List.drop 1
                        |> List.head
                        |> Maybe.andThen .modelState
                        |> Maybe.withDefault ""
                        |> String.contains "selected = 1"
                        |> Expect.equal True
            ]
        ]



-- Mini Git model


type alias Commit =
    { sha : String
    , message : String
    }


type alias Model =
    { commits : List Commit
    , selected : Int
    , scrollOffset : Int
    }


type Msg
    = KeyPressed Tui.KeyEvent
    | MouseEvent Tui.MouseEvent


sampleCommits : List Commit
sampleCommits =
    [ { sha = "abc1234", message = "Initial commit" }
    , { sha = "def5678", message = "Add feature" }
    , { sha = "345cdef", message = "Fix bug" }
    , { sha = "789abcd", message = "Update docs" }
    ]


longCommitList : List Commit
longCommitList =
    List.range 1 20
        |> List.map
            (\i ->
                { sha = "sha" ++ String.padLeft 4 '0' (String.fromInt i)
                , message = "Commit " ++ String.fromInt i
                }
            )


miniGitInit : List Commit -> ( Model, Effect Msg )
miniGitInit commits =
    ( { commits = commits
      , selected = 0
      , scrollOffset = 0
      }
    , Effect.none
    )


miniGitUpdate : Msg -> Model -> ( Model, Effect Msg )
miniGitUpdate msg model =
    let
        maxIndex : Int
        maxIndex =
            List.length model.commits - 1
    in
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Character 'j' ->
                    ( { model | selected = min maxIndex (model.selected + 1) }
                        |> adjustScroll
                    , Effect.none
                    )

                Tui.Arrow Tui.Down ->
                    ( { model | selected = min maxIndex (model.selected + 1) }
                        |> adjustScroll
                    , Effect.none
                    )

                Tui.Character 'k' ->
                    ( { model | selected = max 0 (model.selected - 1) }
                        |> adjustScroll
                    , Effect.none
                    )

                Tui.Arrow Tui.Up ->
                    ( { model | selected = max 0 (model.selected - 1) }
                        |> adjustScroll
                    , Effect.none
                    )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )

        MouseEvent event ->
            case event of
                Tui.Click { row } ->
                    let
                        -- Row 2 is the header, commits start at row 2 (0-indexed)
                        clickedIndex : Int
                        clickedIndex =
                            row - 2 + model.scrollOffset
                    in
                    if clickedIndex >= 0 && clickedIndex <= maxIndex then
                        ( { model | selected = clickedIndex }
                        , Effect.none
                        )

                    else
                        ( model, Effect.none )

                Tui.ScrollUp _ ->
                    ( { model | selected = max 0 (model.selected - 1) }
                        |> adjustScroll
                    , Effect.none
                    )

                Tui.ScrollDown _ ->
                    ( { model | selected = min maxIndex (model.selected + 1) }
                        |> adjustScroll
                    , Effect.none
                    )


adjustScroll : Model -> Model
adjustScroll model =
    -- Simple scrolling: keep selected item visible
    -- Assume a visible window of some height, adjusted in view
    if model.selected < model.scrollOffset then
        { model | scrollOffset = model.selected }

    else if model.selected >= model.scrollOffset + 5 then
        -- 5 visible rows (rough)
        { model | scrollOffset = model.selected - 4 }

    else
        model


miniGitView : Tui.Context -> Model -> Tui.Screen
miniGitView ctx model =
    let
        dimStyle : Tui.Style
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] }

        headerStyle : Tui.Style
        headerStyle =
            { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.bold ] }

        separator : String
        separator =
            String.repeat (ctx.width // 3) "─"

        visibleRows : Int
        visibleRows =
            ctx.height - 5

        visibleCommits : List ( Int, Commit )
        visibleCommits =
            model.commits
                |> List.indexedMap Tuple.pair
                |> List.drop model.scrollOffset
                |> List.take visibleRows

        commitList : Tui.Screen
        commitList =
            visibleCommits
                |> List.map
                    (\( i, commit ) ->
                        let
                            isSelected : Bool
                            isSelected =
                                i == model.selected
                        in
                        Tui.concat
                            [ Tui.text
                                (if isSelected then
                                    "▸ "

                                 else
                                    "  "
                                )
                            , Tui.styled
                                (if isSelected then
                                    { fg = Just Ansi.Color.yellow
                                    , bg = Nothing
                                    , attributes = [ Tui.bold ]
                                    }

                                 else
                                    dimStyle
                                )
                                commit.sha
                            , Tui.text " "
                            , Tui.text (truncate (ctx.width // 3 - 12) commit.message)
                            ]
                    )
                |> Tui.lines

        selectedCommit : Tui.Screen
        selectedCommit =
            case model.commits |> List.drop model.selected |> List.head of
                Just commit ->
                    Tui.lines
                        [ Tui.styled headerStyle "Commit Detail"
                        , Tui.text ""
                        , Tui.concat
                            [ Tui.styled dimStyle "SHA: "
                            , Tui.text commit.sha
                            ]
                        , Tui.text ""
                        , Tui.text commit.message
                        ]

                Nothing ->
                    Tui.text "No commit selected"
    in
    Tui.lines
        [ Tui.styled headerStyle "Mini Git Log"
        , Tui.text ""
        , commitList
        , Tui.text ""
        , Tui.styled dimStyle separator
        , Tui.text ""
        , selectedCommit
        , Tui.text ""
        , Tui.styled dimStyle "j/k navigate  q quit  mouse click/scroll"
        ]


truncate : Int -> String -> String
truncate maxLen str =
    if String.length str > maxLen then
        String.left (maxLen - 1) str ++ "…"

    else
        str


miniGitSubscriptions : Model -> Tui.Sub.Sub Msg
miniGitSubscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse MouseEvent
        ]


miniGitTest : TuiTest.TuiTest Model Msg
miniGitTest =
    TuiTest.start
        { data = sampleCommits
        , init = miniGitInit
        , update = miniGitUpdate
        , view = miniGitView
        , subscriptions = miniGitSubscriptions
        }
