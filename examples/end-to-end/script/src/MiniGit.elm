module MiniGit exposing (run)

{-| Mini lazygit — browse git log with split panes, selectable list, and diff view.

    elm - pages run script / src / MiniGit.elm

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Layout as Layout
import Tui.Sub


type alias Commit =
    { sha : String
    , message : String
    }


type alias Model =
    { layout : Layout.State
    , commits : List Commit
    , diffContent : String
    }


type Msg
    = KeyPressed Tui.KeyEvent
    | Mouse Tui.MouseEvent
    | SelectCommit Int
    | GotDiff (Result FatalError String)


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
    ( { layout = Layout.init
      , commits = commits
      , diffContent = ""
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


update : Msg -> Model -> ( Model, Effect.Effect Msg )
update msg model =
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Character 'j' ->
                    let
                        newLayout : Layout.State
                        newLayout =
                            Layout.navigateDown "commits" model.layout

                        newIndex : Int
                        newIndex =
                            Layout.selectedIndex "commits" newLayout
                    in
                    ( { model | layout = newLayout }
                    , loadDiffForIndex newIndex model.commits
                    )

                Tui.Arrow Tui.Down ->
                    let
                        newLayout : Layout.State
                        newLayout =
                            Layout.navigateDown "commits" model.layout

                        newIndex : Int
                        newIndex =
                            Layout.selectedIndex "commits" newLayout
                    in
                    ( { model | layout = newLayout }
                    , loadDiffForIndex newIndex model.commits
                    )

                Tui.Character 'k' ->
                    let
                        newLayout : Layout.State
                        newLayout =
                            Layout.navigateUp "commits" model.layout

                        newIndex : Int
                        newIndex =
                            Layout.selectedIndex "commits" newLayout
                    in
                    ( { model | layout = newLayout }
                    , loadDiffForIndex newIndex model.commits
                    )

                Tui.Arrow Tui.Up ->
                    let
                        newLayout : Layout.State
                        newLayout =
                            Layout.navigateUp "commits" model.layout

                        newIndex : Int
                        newIndex =
                            Layout.selectedIndex "commits" newLayout
                    in
                    ( { model | layout = newLayout }
                    , loadDiffForIndex newIndex model.commits
                    )

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )

        Mouse mouseEvent ->
            let
                ( newLayout, maybeMsg ) =
                    Layout.handleMouse mouseEvent (myLayout model) model.layout
            in
            case maybeMsg of
                Just userMsg ->
                    update userMsg { model | layout = newLayout }

                Nothing ->
                    ( { model | layout = newLayout }, Effect.none )

        SelectCommit index ->
            ( model
            , loadDiffForIndex index model.commits
            )

        GotDiff result ->
            ( { model
                | diffContent =
                    case result of
                        Ok content ->
                            content

                        Err _ ->
                            "(error loading diff)"
              }
            , Effect.none
            )


myLayout : Model -> Layout.Layout Msg
myLayout model =
    Layout.horizontal
        [ Layout.pane "commits"
            { title = "Commits", width = Layout.fill }
            (Layout.selectableList
                { onSelect = SelectCommit
                , selected =
                    \commit ->
                        Tui.styled
                            { fg = Just Ansi.Color.yellow
                            , bg = Nothing
                            , attributes = [ Tui.bold ]
                            }
                            ("▸ " ++ commit.sha ++ " " ++ commit.message)
                , default =
                    \commit ->
                        Tui.text ("  " ++ commit.sha ++ " " ++ commit.message)
                }
                model.commits
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


view : Tui.Context -> Model -> Tui.Screen
view ctx model =
    myLayout model
        |> Layout.toScreen (Layout.withContext { width = ctx.width, height = ctx.height } model.layout)


styleDiffLine : String -> Tui.Screen
styleDiffLine line =
    if String.startsWith "+" line && not (String.startsWith "+++" line) then
        Tui.styled { fg = Just Ansi.Color.green, bg = Nothing, attributes = [] } line

    else if String.startsWith "-" line && not (String.startsWith "---" line) then
        Tui.styled { fg = Just Ansi.Color.red, bg = Nothing, attributes = [] } line

    else if String.startsWith "@@" line then
        Tui.styled { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [] } line

    else if String.startsWith "commit " line || String.startsWith "Author:" line || String.startsWith "Date:" line then
        Tui.styled { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [] } line

    else
        Tui.styled { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] } line


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse Mouse
        ]
