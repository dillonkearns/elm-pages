module MiniGit exposing (run)

{-| Mini lazygit — browse git log with split panes, selectable list, and diff view.

Uses the declarative TUI API (`Layout.compileApp`) — no manual key routing,
subscription wiring, or Layout.State management.

    elm - pages run script / src / MiniGit.elm

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Layout as Layout
import Tui.Program


type alias Commit =
    { sha : String
    , message : String
    }


type alias Model =
    { commits : List Commit
    , diffContent : String
    , activeOp : Maybe String
    , modal : Maybe ModalKind
    }


type ModalKind
    = CommitDialog
    | HelpView


type Msg
    = SelectCommit Commit
    | GotDiff (Result FatalError String)
    | OpenCommitDialog
    | SubmitCommit String
    | CloseModal
    | OpenHelp
    | Quit


run : Script
run =
    Tui.Program.program
        (Layout.compileApp
            { data = loadCommits
            , init = init
            , update = update
            , view = view
            , bindings = bindings
            , status = status
            , modal = modal
            , onRawEvent = Nothing
            }
        )


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



-- INIT


init : List Commit -> ( Model, Effect.Effect Msg )
init commits =
    ( { commits = commits
      , diffContent = ""
      , activeOp = Nothing
      , modal = Nothing
      }
    , Effect.none
    )



-- UPDATE


update : Layout.UpdateContext -> Msg -> Model -> ( Model, Effect.Effect Msg )
update _ msg model =
    case msg of
        SelectCommit commit ->
            ( { model | activeOp = Just "Loading diff..." }
            , Effect.batch
                [ Script.command "git" [ "show", "--stat", "-p", commit.sha ]
                    |> Effect.attempt GotDiff
                , Effect.resetScroll "diff"
                ]
            )

        GotDiff (Ok content_) ->
            ( { model | diffContent = content_, activeOp = Nothing }, Effect.none )

        GotDiff (Err _) ->
            ( { model | diffContent = "(error loading diff)", activeOp = Nothing }
            , Effect.errorToast "Failed to load diff"
            )

        OpenCommitDialog ->
            ( { model | modal = Just CommitDialog }, Effect.none )

        SubmitCommit message ->
            if String.isEmpty message then
                ( { model | modal = Nothing }
                , Effect.errorToast "(empty commit message)"
                )

            else
                ( { model | modal = Nothing }
                , Effect.toast ("Committed: " ++ message)
                )

        CloseModal ->
            ( { model | modal = Nothing }, Effect.none )

        OpenHelp ->
            ( { model | modal = Just HelpView }, Effect.none )

        Quit ->
            ( model, Effect.exit )



-- VIEW


view : Tui.Context -> Model -> Layout.Layout Msg
view ctx model =
    let
        panes =
            [ Layout.pane "commits"
                { title = "Commits", width = Layout.fill }
                (Layout.selectableList
                    { onSelect = \commit -> SelectCommit commit
                    , view =
                        \{ selection } commit ->
                            case selection of
                                Layout.Selected { focused } ->
                                    Tui.concat
                                        [ Tui.text "▸"
                                            |> (if focused then Tui.fg Ansi.Color.yellow else identity)
                                        , Tui.text " "
                                        , Tui.text commit.sha
                                            |> (if focused then Tui.fg Ansi.Color.yellow >> Tui.bold else Tui.bold)
                                        , Tui.text " "
                                        , Tui.text commit.message
                                        ]
                                        |> (if focused then Tui.bg Ansi.Color.blue else identity)

                                Layout.NotSelected ->
                                    Tui.concat
                                        [ Tui.text " "
                                        , Tui.text " "
                                        , Tui.text commit.sha |> Tui.dim
                                        , Tui.text " "
                                        , Tui.text commit.message
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
                        |> List.map styleDiffLine
                    )
                    |> Layout.withSearchable
                )
            ]
    in
    if ctx.width <= 84 && ctx.height > 45 then
        Layout.vertical panes

    else
        Layout.horizontal panes


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



-- BINDINGS


bindings : { focusedPane : Maybe String } -> Model -> List (Layout.Group Msg)
bindings _ _ =
    [ Layout.group "Actions"
        [ Layout.charBinding 'c' "Commit" OpenCommitDialog
        , Layout.charBinding '?' "Help" OpenHelp
        , Layout.charBinding 'q' "Quit" Quit
        ]
    ]



-- STATUS


status : Model -> { waiting : Maybe String }
status model =
    { waiting = model.activeOp }



-- MODAL


modal : Model -> Maybe (Layout.Modal Msg)
modal model =
    case model.modal of
        Just CommitDialog ->
            Just
                (Layout.promptModal
                    { title = "Commit Message"
                    , initialValue = ""
                    , onSubmit = SubmitCommit
                    , onCancel = CloseModal
                    }
                )

        Just HelpView ->
            Just (Layout.helpModal CloseModal)

        Nothing ->
            Nothing
