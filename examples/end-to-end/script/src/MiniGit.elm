module MiniGit exposing (run)

{-| Mini lazygit — browse git log with keyboard and mouse.

    elm - pages run script / src / MiniGit.elm

Keys: j/k or ↑/↓ navigate, q quit. Mouse: click to select, scroll to navigate.

-}

import Ansi.Color
import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Pages.Script as Script exposing (Script)
import Tui
import Tui.Effect as Effect
import Tui.Sub


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
        [ "log", "--oneline", "-30", "--format=%h %s" ]
        |> BackendTask.map parseCommits


parseCommits : String -> List Commit
parseCommits output =
    output
        |> String.trim
        |> String.lines
        |> List.map
            (\line ->
                case String.split " " line of
                    sha :: rest ->
                        { sha = sha, message = String.join " " rest }

                    _ ->
                        { sha = "?", message = line }
            )


init : List Commit -> ( Model, Effect.Effect Msg )
init commits =
    ( { commits = commits
      , selected = 0
      , scrollOffset = 0
      }
    , Effect.none
    )


update : Msg -> Model -> ( Model, Effect.Effect Msg )
update msg model =
    let
        maxIndex : Int
        maxIndex =
            List.length model.commits - 1
    in
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Character 'j' ->
                    ( moveDown maxIndex model, Effect.none )

                Tui.Arrow Tui.Down ->
                    ( moveDown maxIndex model, Effect.none )

                Tui.Character 'k' ->
                    ( moveUp model, Effect.none )

                Tui.Arrow Tui.Up ->
                    ( moveUp model, Effect.none )

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
                        clickedIndex : Int
                        clickedIndex =
                            row - 2 + model.scrollOffset
                    in
                    if clickedIndex >= 0 && clickedIndex <= maxIndex then
                        ( { model | selected = clickedIndex }, Effect.none )

                    else
                        ( model, Effect.none )

                Tui.ScrollDown _ ->
                    ( moveDown maxIndex model, Effect.none )

                Tui.ScrollUp _ ->
                    ( moveUp model, Effect.none )


moveDown : Int -> Model -> Model
moveDown maxIndex model =
    adjustScroll { model | selected = min maxIndex (model.selected + 1) }


moveUp : Model -> Model
moveUp model =
    adjustScroll { model | selected = max 0 (model.selected - 1) }


adjustScroll : Model -> Model
adjustScroll model =
    if model.selected < model.scrollOffset then
        { model | scrollOffset = model.selected }

    else if model.selected >= model.scrollOffset + 5 then
        { model | scrollOffset = model.selected - 4 }

    else
        model


view : Tui.Context -> Model -> Tui.Screen
view ctx model =
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
            max 1 (ctx.height - 8)

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
        , Tui.styled dimStyle "j/k navigate  q quit  click/scroll"
        ]


truncate : Int -> String -> String
truncate maxLen str =
    if String.length str > maxLen then
        String.left (maxLen - 1) str ++ "…"

    else
        str


subscriptions : Model -> Tui.Sub.Sub Msg
subscriptions _ =
    Tui.Sub.batch
        [ Tui.Sub.onKeyPress KeyPressed
        , Tui.Sub.onMouse MouseEvent
        ]
