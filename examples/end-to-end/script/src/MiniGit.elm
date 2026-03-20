module MiniGit exposing (run)

{-| Mini lazygit — browse git log with split panes, selectable list, and diff view.

    elm - pages run script / src / MiniGit.elm

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)
import Tui exposing (plain)
import Tui.Effect as Effect
import Tui.Input as Input
import Tui.Keybinding as Keybinding
import Tui.Layout as Layout
import Tui.Modal
import Tui.Sub
import Tui.Toast as Toast


type alias Commit =
    { sha : String
    , message : String
    }


type alias Model =
    { layout : Layout.State
    , commits : List Commit
    , diffContent : String
    , modal : Maybe ModalState
    , toasts : Toast.State
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
    | DoSwitchPane
    | DoQuit
    | DoOpenCommit
    | DoOpenHelp
    | DoScrollDiff Int


type Msg
    = KeyPressed Tui.KeyEvent
    | Mouse Tui.MouseEvent
    | GotPaste String
    | GotContext { width : Int, height : Int }
    | SelectCommit Int
    | GotDiff (Result FatalError String)
    | ToastTick


run : Script
run =
    Script.tui
        { data = loadCommits
        , init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


loadCommits : BackendTask FatalError (List Commit)
loadCommits =
    Script.command "git"
        [ "log", "--oneline", "-50", "--format=%h %s" ]
        |> BackendTask.map parseCommits


parseCommits : String -> List Commit
parseCommits output =
    output
        |> String.trim
        |> String.lines
        |> List.filterMap
            (\line ->
                case String.split " " line of
                    sha :: rest ->
                        Just { sha = sha, message = String.join " " rest }

                    _ ->
                        Nothing
            )


init : List Commit -> ( Model, Effect.Effect Msg )
init commits =
    ( { layout = Layout.init |> Layout.focusPane "commits"
      , commits = commits
      , diffContent = ""
      , modal = Nothing
      , toasts = Toast.init
      }
    , loadDiffForIndex 0 commits
    )


loadDiffForIndex : Int -> List Commit -> Effect.Effect Msg
loadDiffForIndex index commits =
    case commits |> List.drop index |> List.head of
        Just commit ->
            Script.command "git" [ "show", "--stat", "-p", commit.sha ]
                |> Effect.attempt
                    (\result ->
                        GotDiff
                            (case result of
                                Ok content ->
                                    Ok content

                                Err _ ->
                                    Ok "(failed to load diff)"
                            )
                    )

        Nothing ->
            Effect.none



-- KEYBINDINGS


globalBindings : Keybinding.Group Action
globalBindings =
    Keybinding.group "Global"
        [ Keybinding.binding (Tui.Character 'q') "Quit" DoQuit
        , Keybinding.binding Tui.Tab "Switch pane" DoSwitchPane
        , Keybinding.binding (Tui.Character 'c') "Commit" DoOpenCommit
        , Keybinding.binding (Tui.Character '?') "Help" DoOpenHelp
        ]


commitPaneBindings : Keybinding.Group Action
commitPaneBindings =
    Keybinding.group "Commits"
        [ Keybinding.binding (Tui.Character 'j') "Next commit" (DoNavigate 1)
            |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
        , Keybinding.binding (Tui.Character 'k') "Previous commit" (DoNavigate -1)
            |> Keybinding.withAlternate (Tui.Arrow Tui.Up)
        ]


diffPaneBindings : Keybinding.Group Action
diffPaneBindings =
    Keybinding.group "Diff"
        [ Keybinding.binding (Tui.Character 'j') "Scroll down" (DoScrollDiff 3)
            |> Keybinding.withAlternate (Tui.Arrow Tui.Down)
        , Keybinding.binding (Tui.Character 'k') "Scroll up" (DoScrollDiff -3)
            |> Keybinding.withAlternate (Tui.Arrow Tui.Up)
        ]


activeBindings : Model -> List (Keybinding.Group Action)
activeBindings model =
    case Layout.focusedPane model.layout of
        Just "commits" ->
            [ commitPaneBindings, globalBindings ]

        Just "diff" ->
            [ diffPaneBindings, globalBindings ]

        _ ->
            [ globalBindings ]


allBindings : Model -> List (Keybinding.Group Action)
allBindings model =
    case Layout.focusedPane model.layout of
        Just "commits" ->
            [ commitPaneBindings, globalBindings ]

        Just "diff" ->
            [ diffPaneBindings, globalBindings ]

        _ ->
            [ globalBindings ]


handleAction : Action -> Model -> ( Model, Effect.Effect Msg )
handleAction action model =
    case action of
        DoNavigate direction ->
            navigateInFocusedPane direction model

        DoSwitchPane ->
            let
                nextFocus =
                    if Layout.focusedPane model.layout == Just "commits" then
                        "diff"

                    else
                        "commits"
            in
            ( { model | layout = Layout.focusPane nextFocus model.layout }
            , Effect.none
            )

        DoQuit ->
            ( model, Effect.exit )

        DoOpenCommit ->
            ( { model | modal = Just (CommitModal { input = Input.init "" }) }
            , Effect.none
            )

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

        DoScrollDiff delta ->
            let
                newLayout =
                    if delta > 0 then
                        Layout.scrollDown "diff" delta model.layout

                    else
                        Layout.scrollUp "diff" (abs delta) model.layout
            in
            ( { model | layout = newLayout }, Effect.none )



-- UPDATE


update : Msg -> Model -> ( Model, Effect.Effect Msg )
update msg model =
    -- Toast ticks run regardless of modal state
    case msg of
        ToastTick ->
            ( { model | toasts = Toast.tick model.toasts }, Effect.none )

        _ ->
            updateMain msg model


updateMain : Msg -> Model -> ( Model, Effect.Effect Msg )
updateMain msg model =
    case model.modal of
        Just (CommitModal modalState) ->
            case msg of
                KeyPressed event ->
                    case event.key of
                        Tui.Escape ->
                            ( { model | modal = Nothing }, Effect.none )

                        Tui.Enter ->
                            let
                                commitMsg =
                                    Input.text modalState.input
                            in
                            ( { model
                                | modal = Nothing
                                , toasts =
                                    if String.isEmpty commitMsg then
                                        Toast.errorToast "(empty commit message)" model.toasts

                                    else
                                        Toast.toast ("Committed: " ++ commitMsg) model.toasts
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

                GotContext ctx ->
                    ( { model | layout = Layout.withContext ctx model.layout }, Effect.none )

                _ ->
                    ( model, Effect.none )

        Just (HelpModal helpState) ->
            case msg of
                KeyPressed event ->
                    case helpState.mode of
                        HelpBrowse ->
                            case event.key of
                                Tui.Escape ->
                                    ( { model | modal = Nothing }, Effect.none )

                                Tui.Character '/' ->
                                    -- Enter search mode
                                    ( { model | modal = Just (HelpModal { helpState | mode = HelpSearch }) }
                                    , Effect.none
                                    )

                                Tui.Character 'j' ->
                                    ( { model | modal = Just (HelpModal { helpState | selectedIndex = helpState.selectedIndex + 1 }) }
                                    , Effect.none
                                    )

                                Tui.Arrow Tui.Down ->
                                    ( { model | modal = Just (HelpModal { helpState | selectedIndex = helpState.selectedIndex + 1 }) }
                                    , Effect.none
                                    )

                                Tui.Character 'k' ->
                                    ( { model | modal = Just (HelpModal { helpState | selectedIndex = max 0 (helpState.selectedIndex - 1) }) }
                                    , Effect.none
                                    )

                                Tui.Arrow Tui.Up ->
                                    ( { model | modal = Just (HelpModal { helpState | selectedIndex = max 0 (helpState.selectedIndex - 1) }) }
                                    , Effect.none
                                    )

                                _ ->
                                    -- Fall through to global bindings (q to quit, etc.)
                                    case Keybinding.dispatch [ globalBindings ] event of
                                        Just action ->
                                            handleAction action { model | modal = Nothing }

                                        Nothing ->
                                            ( model, Effect.none )

                        HelpSearch ->
                            case event.key of
                                Tui.Escape ->
                                    -- Exit search mode back to browse (don't close modal)
                                    ( { model | modal = Just (HelpModal { helpState | mode = HelpBrowse }) }
                                    , Effect.none
                                    )

                                Tui.Enter ->
                                    -- Confirm search, return to browse
                                    ( { model | modal = Just (HelpModal { helpState | mode = HelpBrowse, selectedIndex = 0 }) }
                                    , Effect.none
                                    )

                                _ ->
                                    -- Type into filter
                                    ( { model
                                        | modal =
                                            Just
                                                (HelpModal
                                                    { helpState
                                                        | filter = Input.update event helpState.filter
                                                        , selectedIndex = 0
                                                    }
                                                )
                                      }
                                    , Effect.none
                                    )

                GotPaste pastedText ->
                    case helpState.mode of
                        HelpSearch ->
                            ( { model
                                | modal =
                                    Just
                                        (HelpModal
                                            { helpState
                                                | filter = Input.insertText pastedText helpState.filter
                                                , selectedIndex = 0
                                            }
                                        )
                              }
                            , Effect.none
                            )

                        HelpBrowse ->
                            ( model, Effect.none )

                GotContext ctx ->
                    ( { model | layout = Layout.withContext ctx model.layout }, Effect.none )

                _ ->
                    ( model, Effect.none )

        Nothing ->
            case msg of
                KeyPressed event ->
                    case Keybinding.dispatch (activeBindings model) event of
                        Just action ->
                            handleAction action model

                        Nothing ->
                            ( model, Effect.none )

                Mouse mouseEvent ->
                    let
                        ( newLayout, maybeMsg ) =
                            Layout.handleMouse mouseEvent
                                (Layout.contextOf model.layout)
                                (myLayout (Layout.contextOf model.layout) model)
                                model.layout
                    in
                    case maybeMsg of
                        Just userMsg ->
                            update userMsg { model | layout = newLayout }

                        Nothing ->
                            ( { model | layout = newLayout }, Effect.none )

                GotPaste _ ->
                    ( model, Effect.none )

                GotContext ctx ->
                    ( { model | layout = Layout.withContext ctx model.layout }
                    , Effect.none
                    )

                SelectCommit index ->
                    ( { model | layout = Layout.resetScroll "diff" model.layout }
                    , loadDiffForIndex index model.commits
                    )

                GotDiff result ->
                    ( { model
                        | diffContent =
                            case result of
                                Ok content_ ->
                                    content_

                                Err _ ->
                                    "(error loading diff)"
                      }
                    , Effect.none
                    )

                ToastTick ->
                    -- Handled at top level of update
                    ( model, Effect.none )


navigateInFocusedPane : Int -> Model -> ( Model, Effect.Effect Msg )
navigateInFocusedPane direction model =
    case Layout.focusedPane model.layout of
        Just "commits" ->
            let
                ( newLayout, maybeMsg ) =
                    (if direction > 0 then
                        Layout.navigateDown "commits" (myLayout (Layout.contextOf model.layout) model)

                     else
                        Layout.navigateUp "commits" (myLayout (Layout.contextOf model.layout) model)
                    )
                        model.layout
            in
            -- navigateDown/Up fires onSelect (SelectCommit) when selection changes.
            -- Handle it through update just like a click — unified path!
            case maybeMsg of
                Just userMsg ->
                    update userMsg { model | layout = newLayout }

                Nothing ->
                    ( { model | layout = newLayout }, Effect.none )

        _ ->
            ( model, Effect.none )



-- LAYOUT


{-| Build the layout. Direction is decided by the caller (view function)
based on terminal dimensions — NOT here, to avoid stale context issues.
-}
myPanes : Model -> List (Layout.Pane Msg)
myPanes model =
    let
        selectedIdx =
            Layout.selectedIndex "commits" model.layout

        commitCount =
            List.length model.commits
    in
    [ Layout.pane "commits"
        { title = "Commits", width = Layout.fill }
        (Layout.selectableList
            { onSelect = SelectCommit
            , selected =
                \commit ->
                    Tui.spaced
                        [ Tui.text "▸" |> Tui.fg Ansi.Color.yellow
                        , Tui.text commit.sha |> Tui.fg Ansi.Color.yellow |> Tui.bold
                        , Tui.text commit.message
                        ]
                        |> Tui.bg Ansi.Color.blue
            , default =
                \commit ->
                    Tui.spaced
                        [ Tui.text " "
                        , Tui.text commit.sha |> Tui.dim
                        , Tui.text commit.message
                        ]
            }
            model.commits
        )
        |> Layout.withPrefix "[1]"
        |> Layout.withFooterScreen
            (Tui.spaced
                [ Tui.text (String.fromInt (selectedIdx + 1)) |> Tui.bold |> Tui.fg Ansi.Color.cyan
                , Tui.text "of" |> Tui.dim
                , Tui.text (String.fromInt commitCount) |> Tui.bold |> Tui.fg Ansi.Color.cyan
                ]
            )
    , Layout.pane "diff"
        { title = "Diff", width = Layout.fillPortion 2 }
        (Layout.content
            (model.diffContent
                |> String.lines
                |> List.map styleDiffLine
            )
        )
    ]


{-| Build the layout with direction based on terminal dimensions.
Lazygit breakpoint: narrow + tall → vertical (portrait) mode.
-}
myLayout : { width : Int, height : Int } -> Model -> Layout.Layout Msg
myLayout dimensions model =
    let
        panes =
            myPanes model
    in
    if dimensions.width <= 84 && dimensions.height > 45 then
        Layout.vertical panes

    else
        Layout.horizontal panes



-- VIEW


view : Tui.Context -> Model -> Tui.Screen
view ctx model =
    let
        layoutState =
            Layout.withContext { width = ctx.width, height = ctx.height } model.layout

        bgRows =
            Layout.toRows layoutState (myLayout { width = ctx.width, height = ctx.height } model)

        rows =
            case model.modal of
                Just (CommitModal modalState) ->
                    let
                        modalWidth =
                            min 60 (ctx.width - 4)
                    in
                    Tui.Modal.overlay
                        { title = "Commit"
                        , body =
                            [ Tui.text ""
                            , Input.view { width = modalWidth - 2 } modalState.input
                            , Tui.text ""
                            ]
                        , footer = "Enter: confirm │ Esc: cancel"
                        , width = modalWidth
                        }
                        { width = ctx.width, height = ctx.height }
                        bgRows

                Just (HelpModal helpState) ->
                    let
                        filterText =
                            Input.text helpState.filter

                        modalWidth =
                            min 60 (ctx.width - 4)

                        groups =
                            allBindings model

                        -- Clamp selected index to valid range
                        rowCount =
                            Keybinding.helpRowCount filterText groups

                        clampedIdx =
                            clamp 0 (max 0 (rowCount - 1)) helpState.selectedIndex

                        helpBody =
                            Keybinding.helpRowsWithSelection clampedIdx filterText groups
                                ++ [ Tui.text "" ]
                                ++ Layout.navigationHelpRows

                        searchRow =
                            case helpState.mode of
                                HelpSearch ->
                                    [ Tui.concat
                                        [ Tui.styled
                                            { plain | attributes = [ Tui.Dim ] }
                                            "/"
                                        , Input.view { width = modalWidth - 3 } helpState.filter
                                        ]
                                    , Tui.text ""
                                    ]

                                HelpBrowse ->
                                    if not (String.isEmpty filterText) then
                                        [ Tui.styled
                                            { plain | attributes = [ Tui.Dim ] }
                                            ("/" ++ filterText)
                                        , Tui.text ""
                                        ]

                                    else
                                        []

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
                        , width = modalWidth
                        }
                        { width = ctx.width, height = ctx.height }
                        bgRows

                Nothing ->
                    bgRows

        -- Overlay toast on the last row when active
        finalRows =
            if Toast.hasToasts model.toasts then
                case List.reverse rows of
                    _ :: rest ->
                        List.reverse (Toast.view model.toasts :: rest)

                    [] ->
                        [ Toast.view model.toasts ]

            else
                rows
    in
    Tui.lines finalRows


styleDiffLine : String -> Tui.Screen
styleDiffLine line =
    if String.startsWith "+" line && not (String.startsWith "+++" line) then
        Tui.text line |> Tui.fg Ansi.Color.green

    else if String.startsWith "-" line && not (String.startsWith "---" line) then
        Tui.text line |> Tui.fg Ansi.Color.red

    else if String.startsWith "@@" line then
        Tui.text line |> Tui.fg Ansi.Color.cyan

    else if String.startsWith "commit " line || String.startsWith "Author:" line || String.startsWith "Date:" line then
        Tui.text line |> Tui.fg Ansi.Color.yellow

    else
        Tui.text line |> Tui.dim


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions model =
    Tui.Sub.batch
        ([ Tui.Sub.onKeyPress KeyPressed
         , Tui.Sub.onMouse Mouse
         , Tui.Sub.onPaste GotPaste
         , Tui.Sub.onContext GotContext
         ]
            ++ (if Toast.hasToasts model.toasts then
                    [ Tui.Sub.every 100 ToastTick ]

                else
                    []
               )
        )
