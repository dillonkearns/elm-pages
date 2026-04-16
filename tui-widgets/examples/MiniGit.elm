module MiniGit exposing
    ( initialModel
    , initialModelWithContext
    , miniGitLayout
    , miniGitTest
    , run
    , sampleCommits
    )

import Ansi.Color
import BackendTask exposing (BackendTask)
import Pages.Script exposing (Script)
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Input as Input
import Tui.Keybinding as Keybinding
import Tui.Layout as Layout
import Tui.Modal
import Tui.Screen exposing (plain)
import Tui.Sub
import Tui.Test as TuiTest


type alias Commit =
    { sha : String
    , message : String
    }


type alias Model =
    { layout : Layout.State
    , commits : List Commit
    , diffContent : String
    , modal : Maybe ModalState
    , lastAction : String
    }


type ModalState
    = CommitModal { input : Input.State }
    | HelpModal HelpState


type alias HelpState =
    { mode : HelpMode
    , filter : Input.State
    , selectedIndex : Int
    }


type HelpMode
    = HelpBrowse
    | HelpSearch


type Action
    = DoNavigate Int
    | DoScrollDiff Int
    | DoQuit
    | DoSwitchPane
    | DoOpenCommit
    | DoOpenHelp


type Msg
    = KeyPressed Tui.Sub.KeyEvent
    | Mouse Tui.Sub.MouseEvent
    | GotPaste String
    | Resized { width : Int, height : Int }
    | SelectCommit Commit


run : Script
run =
    Tui.program
        { data = BackendTask.succeed sampleCommits
        , init = miniGitInit
        , update = miniGitUpdate
        , view = miniGitView
        , subscriptions = miniGitSubscriptions
        }


testGlobalBindings : Keybinding.Group Action
testGlobalBindings =
    Keybinding.group "Global"
        [ Keybinding.binding (Tui.Sub.Character 'q') "Quit" DoQuit
        , Keybinding.binding Tui.Sub.Tab "Switch pane" DoSwitchPane
        , Keybinding.binding (Tui.Sub.Character 'c') "Commit" DoOpenCommit
        , Keybinding.binding (Tui.Sub.Character '?') "Help" DoOpenHelp
        ]


testCommitBindings : Keybinding.Group Action
testCommitBindings =
    Keybinding.group "Commits"
        [ Keybinding.binding (Tui.Sub.Character 'j') "Next commit" (DoNavigate 1)
            |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Down)
        , Keybinding.binding (Tui.Sub.Character 'k') "Previous commit" (DoNavigate -1)
            |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Up)
        ]


testDiffBindings : Keybinding.Group Action
testDiffBindings =
    Keybinding.group "Diff"
        [ Keybinding.binding (Tui.Sub.Character 'j') "Scroll down" (DoScrollDiff 3)
            |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Down)
        , Keybinding.binding (Tui.Sub.Character 'k') "Scroll up" (DoScrollDiff -3)
            |> Keybinding.withAlternate (Tui.Sub.Arrow Tui.Sub.Up)
        ]


testActiveBindings : Model -> List (Keybinding.Group Action)
testActiveBindings model =
    case Layout.focusedPane model.layout of
        Just "diff" ->
            [ testDiffBindings, testGlobalBindings ]

        _ ->
            [ testCommitBindings, testGlobalBindings ]


sampleCommits : List Commit
sampleCommits =
    [ { sha = "abc1234", message = "Initial commit" }
    , { sha = "def5678", message = "Add feature" }
    , { sha = "345cdef", message = "Fix bug" }
    , { sha = "789abcd", message = "Update docs" }
    , { sha = "aaa1111", message = "Refactor" }
    , { sha = "bbb2222", message = "Add tests" }
    ]


initialModel : Model
initialModel =
    miniGitInit sampleCommits
        |> Tuple.first


initialModelWithContext : { width : Int, height : Int } -> Model
initialModelWithContext context =
    { initialModel | layout = Layout.withContext context initialModel.layout }


miniGitInit : List Commit -> ( Model, Effect Msg )
miniGitInit commits =
    ( { layout = Layout.init |> Layout.focusPane "commits"
      , commits = commits
      , diffContent = diffForCommit "abc1234"
      , modal = Nothing
      , lastAction = ""
      }
    , Effect.none
    )


diffForCommit : String -> String
diffForCommit sha =
    "commit "
        ++ sha
        ++ "\nAuthor: Test\nDate: today\n\n    Message for "
        ++ sha
        ++ "\n---\n"
        ++ (List.range 1 40
                |> List.map (\i -> "+ line " ++ String.fromInt i ++ " of diff for " ++ sha)
                |> String.join "\n"
           )


miniGitLayout : Model -> Layout.Layout Msg
miniGitLayout model =
    Layout.horizontal
        [ Layout.pane "commits"
            { title = "Commits", width = Layout.fill }
            (Layout.selectableList
                { onSelect = SelectCommit
                , view =
                    \{ selection } commit ->
                        case selection of
                            Layout.Selected { focused } ->
                                Tui.Screen.concat
                                    [ Tui.Screen.text "▸"
                                        |> (if focused then
                                                Tui.Screen.fg Ansi.Color.yellow

                                            else
                                                identity
                                           )
                                    , Tui.Screen.text " "
                                    , Tui.Screen.text commit.sha
                                        |> (if focused then
                                                Tui.Screen.fg Ansi.Color.yellow >> Tui.Screen.bold

                                            else
                                                Tui.Screen.bold
                                           )
                                    , Tui.Screen.text " "
                                    , Tui.Screen.text commit.message
                                    ]
                                    |> (if focused then
                                            Tui.Screen.bg Ansi.Color.blue

                                        else
                                            identity
                                       )

                            Layout.NotSelected ->
                                Tui.Screen.concat
                                    [ Tui.Screen.text " "
                                    , Tui.Screen.text " "
                                    , Tui.Screen.text commit.sha |> Tui.Screen.dim
                                    , Tui.Screen.text " "
                                    , Tui.Screen.text commit.message
                                    ]
                }
                model.commits
                |> Layout.withFilterable
                    (\commit -> commit.sha ++ " " ++ commit.message)
                    model.commits
            )
        , Layout.pane "diff"
            { title = "Diff", width = Layout.fillPortion 2 }
            (Layout.content
                (model.diffContent
                    |> String.lines
                    |> List.map Tui.Screen.text
                )
            )
        ]


miniGitUpdate : Msg -> Model -> ( Model, Effect Msg )
miniGitUpdate msg model =
    case msg of
        Resized context ->
            ( { model | layout = Layout.withContext context model.layout }, Effect.none )

        _ ->
            case model.modal of
                Just (CommitModal modalState) ->
                    case msg of
                        KeyPressed event ->
                            case event.key of
                                Tui.Sub.Escape ->
                                    ( { model | modal = Nothing }, Effect.none )

                                Tui.Sub.Enter ->
                                    let
                                        commitMsg : String
                                        commitMsg =
                                            Input.text modalState.input
                                    in
                                    ( { model
                                        | modal = Nothing
                                        , lastAction =
                                            if String.isEmpty commitMsg then
                                                "(empty commit message)"

                                            else
                                                "Committed: " ++ commitMsg
                                      }
                                    , Effect.none
                                    )

                                _ ->
                                    ( { model | modal = Just (CommitModal { input = Input.update event modalState.input }) }
                                    , Effect.none
                                    )

                        GotPaste pastedText ->
                            ( { model | modal = Just (CommitModal { input = Input.insertText pastedText modalState.input }) }
                            , Effect.none
                            )

                        _ ->
                            ( model, Effect.none )

                Just (HelpModal helpState) ->
                    case msg of
                        KeyPressed event ->
                            case helpState.mode of
                                HelpBrowse ->
                                    case event.key of
                                        Tui.Sub.Escape ->
                                            ( { model | modal = Nothing }, Effect.none )

                                        Tui.Sub.Character '/' ->
                                            ( { model | modal = Just (HelpModal { helpState | mode = HelpSearch }) }, Effect.none )

                                        Tui.Sub.Character 'j' ->
                                            ( { model | modal = Just (HelpModal { helpState | selectedIndex = helpState.selectedIndex + 1 }) }, Effect.none )

                                        Tui.Sub.Arrow Tui.Sub.Down ->
                                            ( { model | modal = Just (HelpModal { helpState | selectedIndex = helpState.selectedIndex + 1 }) }, Effect.none )

                                        Tui.Sub.Character 'k' ->
                                            ( { model | modal = Just (HelpModal { helpState | selectedIndex = max 0 (helpState.selectedIndex - 1) }) }, Effect.none )

                                        Tui.Sub.Arrow Tui.Sub.Up ->
                                            ( { model | modal = Just (HelpModal { helpState | selectedIndex = max 0 (helpState.selectedIndex - 1) }) }, Effect.none )

                                        _ ->
                                            -- Fall through to global bindings
                                            case Keybinding.dispatch [ testGlobalBindings ] event of
                                                Just action ->
                                                    handleAction action { model | modal = Nothing }

                                                Nothing ->
                                                    ( model, Effect.none )

                                HelpSearch ->
                                    case event.key of
                                        Tui.Sub.Escape ->
                                            ( { model | modal = Just (HelpModal { helpState | mode = HelpBrowse }) }, Effect.none )

                                        Tui.Sub.Enter ->
                                            ( { model | modal = Just (HelpModal { helpState | mode = HelpBrowse, selectedIndex = 0 }) }, Effect.none )

                                        _ ->
                                            ( { model | modal = Just (HelpModal { helpState | filter = Input.update event helpState.filter, selectedIndex = 0 }) }, Effect.none )

                        GotPaste pastedText ->
                            case helpState.mode of
                                HelpSearch ->
                                    ( { model | modal = Just (HelpModal { helpState | filter = Input.insertText pastedText helpState.filter, selectedIndex = 0 }) }, Effect.none )

                                HelpBrowse ->
                                    ( model, Effect.none )

                        _ ->
                            ( model, Effect.none )

                Nothing ->
                    case msg of
                        KeyPressed event ->
                            -- Layout handles filter keys (/, typing, Enter, Escape) and
                            -- number keys for pane focus. Check it first.
                            case Layout.handleKeyEvent event (miniGitLayout model) model.layout of
                                ( newLayout, Just layoutMsg, _ ) ->
                                    miniGitUpdate layoutMsg { model | layout = newLayout }

                                ( newLayout, Nothing, True ) ->
                                    ( { model | layout = newLayout }, Effect.none )

                                ( _, Nothing, False ) ->
                                    case Keybinding.dispatch (testActiveBindings model) event of
                                        Just action ->
                                            handleAction action model

                                        Nothing ->
                                            ( model, Effect.none )

                        Mouse mouseEvent ->
                            let
                                ( newLayout, maybeMsg ) =
                                    Layout.handleMouse mouseEvent (Layout.contextOf model.layout) (miniGitLayout model) model.layout
                            in
                            case maybeMsg of
                                Just userMsg ->
                                    miniGitUpdate userMsg { model | layout = newLayout }

                                Nothing ->
                                    ( { model | layout = newLayout }, Effect.none )

                        SelectCommit commit ->
                            ( { model
                                | layout = Layout.resetScroll "diff" model.layout
                                , diffContent = diffForCommit commit.sha
                              }
                            , Effect.none
                            )

                        _ ->
                            ( model, Effect.none )


handleAction : Action -> Model -> ( Model, Effect Msg )
handleAction action model =
    case action of
        DoNavigate direction ->
            let
                ( newLayout, maybeMsg ) =
                    (if direction > 0 then
                        Layout.navigateDown "commits" (miniGitLayout model)

                     else
                        Layout.navigateUp "commits" (miniGitLayout model)
                    )
                        model.layout
            in
            -- navigateDown/Up fires SelectCommit when selection changes
            case maybeMsg of
                Just userMsg ->
                    miniGitUpdate userMsg { model | layout = newLayout }

                Nothing ->
                    ( { model | layout = newLayout }, Effect.none )

        DoQuit ->
            ( model, Effect.exit )

        DoSwitchPane ->
            let
                nextFocus : String
                nextFocus =
                    if Layout.focusedPane model.layout == Just "commits" then
                        "diff"

                    else
                        "commits"
            in
            ( { model | layout = Layout.focusPane nextFocus model.layout }, Effect.none )

        DoScrollDiff delta ->
            let
                newLayout : Layout.State
                newLayout =
                    if delta > 0 then
                        Layout.scrollDown "diff" delta model.layout

                    else
                        Layout.scrollUp "diff" (abs delta) model.layout
            in
            ( { model | layout = newLayout }, Effect.none )

        DoOpenCommit ->
            ( { model | modal = Just (CommitModal { input = Input.init "" }) }, Effect.none )

        DoOpenHelp ->
            ( { model
                | modal =
                    Just
                        (HelpModal
                            { mode = HelpBrowse
                            , filter = Input.init ""
                            , selectedIndex = 0
                            }
                        )
              }
            , Effect.none
            )


miniGitView : Tui.Context -> Model -> Tui.Screen.Screen
miniGitView ctx model =
    let
        layoutState : Layout.State
        layoutState =
            Layout.withContext { width = ctx.width, height = ctx.height } model.layout

        bgRows : List Tui.Screen.Screen
        bgRows =
            Layout.toRows layoutState (miniGitLayout model)

        bottomBar : Tui.Screen.Screen
        bottomBar =
            case Layout.filterStatusBar "commits" model.layout of
                Just filterBar ->
                    filterBar

                Nothing ->
                    if String.isEmpty model.lastAction then
                        Tui.Screen.empty

                    else
                        Tui.Screen.text (" " ++ model.lastAction)
    in
    (case model.modal of
        Just (CommitModal modalState) ->
            Tui.Modal.overlay
                { title = "Commit"
                , body =
                    [ Tui.Screen.text ""
                    , Input.view { width = 40 } modalState.input
                    , Tui.Screen.text ""
                    ]
                , footer = "Enter: confirm │ Esc: cancel"
                , width = 50
                }
                { width = ctx.width, height = ctx.height }
                bgRows

        Just (HelpModal helpState) ->
            let
                filterText : String
                filterText =
                    Input.text helpState.filter

                groups : List (Keybinding.Group Action)
                groups =
                    testActiveBindings model

                rowCount : Int
                rowCount =
                    Keybinding.helpRowCount filterText groups

                clampedIdx : Int
                clampedIdx =
                    clamp 0 (max 0 (rowCount - 1)) helpState.selectedIndex

                helpBody : List Tui.Screen.Screen
                helpBody =
                    Keybinding.helpRowsWithSelection clampedIdx filterText groups

                searchRow : List Tui.Screen.Screen
                searchRow =
                    case helpState.mode of
                        HelpSearch ->
                            [ Tui.Screen.concat
                                [ Tui.Screen.styled { plain | attributes = [ Tui.Screen.Dim ] } "/"
                                , Input.view { width = 40 } helpState.filter
                                ]
                            , Tui.Screen.text ""
                            ]

                        HelpBrowse ->
                            if not (String.isEmpty filterText) then
                                [ Tui.Screen.styled { plain | attributes = [ Tui.Screen.Dim ] } ("/" ++ filterText)
                                , Tui.Screen.text ""
                                ]

                            else
                                []

                footer : String
                footer =
                    case helpState.mode of
                        HelpSearch ->
                            "Enter: confirm │ Esc: cancel"

                        HelpBrowse ->
                            "j/k: navigate │ /: search │ Esc: close"
            in
            Tui.Modal.overlay
                { title = "Keybindings"
                , body = searchRow ++ helpBody
                , footer = footer
                , width = 50
                }
                { width = ctx.width, height = ctx.height }
                bgRows

        Nothing ->
            bgRows
    )
        |> (\rows -> Tui.Screen.lines (List.take (List.length rows - 1) rows ++ [ bottomBar ]))


miniGitSubscriptions : Model -> Tui.Sub.Sub Msg
miniGitSubscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse Mouse
        , Tui.Sub.onPaste GotPaste
        , Tui.Sub.onResize Resized
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
