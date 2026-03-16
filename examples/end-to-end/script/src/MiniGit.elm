module MiniGit exposing (run)

{-| Mini lazygit — browse git log with split panes, box borders, and diff view.

    elm - pages run script / src / MiniGit.elm

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
    , diffContent : String
    , diffScrollOffset : Int
    , leftWidth : Int
    }


type Msg
    = KeyPressed Tui.KeyEvent
    | Mouse Tui.MouseEvent
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
    ( { commits = commits
      , selected = 0
      , scrollOffset = 0
      , diffContent = ""
      , diffScrollOffset = 0
      , leftWidth = 40
      }
    , loadDiff commits
    )


loadDiff : List Commit -> Effect.Effect Msg
loadDiff commits =
    case commits |> List.head of
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
    let
        maxIndex : Int
        maxIndex =
            List.length model.commits - 1
    in
    case msg of
        KeyPressed event ->
            case event.key of
                Tui.Character 'j' ->
                    selectAndLoadDiff (min maxIndex (model.selected + 1)) model

                Tui.Arrow Tui.Down ->
                    selectAndLoadDiff (min maxIndex (model.selected + 1)) model

                Tui.Character 'k' ->
                    selectAndLoadDiff (max 0 (model.selected - 1)) model

                Tui.Arrow Tui.Up ->
                    selectAndLoadDiff (max 0 (model.selected - 1)) model

                Tui.Character 'q' ->
                    ( model, Effect.exit )

                Tui.Escape ->
                    ( model, Effect.exit )

                _ ->
                    ( model, Effect.none )

        Mouse event ->
            case event of
                Tui.Click { row, col } ->
                    if col < model.leftWidth then
                        -- Click in left pane: select commit and load diff
                        let
                            clickedIndex : Int
                            clickedIndex =
                                row - 1 + model.scrollOffset
                        in
                        if clickedIndex >= 0 && clickedIndex <= maxIndex then
                            selectAndLoadDiff clickedIndex model

                        else
                            ( model, Effect.none )

                    else
                        ( model, Effect.none )

                Tui.ScrollDown { col } ->
                    if col < model.leftWidth then
                        -- Scroll in left pane: scroll the commit list viewport
                        ( { model
                            | scrollOffset =
                                min
                                    (max 0 (List.length model.commits - 5))
                                    (model.scrollOffset + 3)
                          }
                        , Effect.none
                        )

                    else
                        -- Scroll in right pane: scroll diff content
                        ( { model
                            | diffScrollOffset =
                                min
                                    (max 0 (List.length (String.lines model.diffContent) - 5))
                                    (model.diffScrollOffset + 3)
                          }
                        , Effect.none
                        )

                Tui.ScrollUp { col } ->
                    if col < model.leftWidth then
                        -- Scroll in left pane: scroll the commit list viewport
                        ( { model | scrollOffset = max 0 (model.scrollOffset - 3) }
                        , Effect.none
                        )

                    else
                        -- Scroll in right pane: scroll diff content
                        ( { model | diffScrollOffset = max 0 (model.diffScrollOffset - 3) }
                        , Effect.none
                        )

        GotDiff result ->
            ( { model
                | diffContent =
                    case result of
                        Ok content ->
                            content

                        Err _ ->
                            "(error loading diff)"
                , diffScrollOffset = 0
              }
            , Effect.none
            )


selectAndLoadDiff : Int -> Model -> ( Model, Effect.Effect Msg )
selectAndLoadDiff newIndex model =
    if newIndex == model.selected then
        ( model, Effect.none )

    else
        let
            newModel : Model
            newModel =
                adjustScroll { model | selected = newIndex, diffScrollOffset = 0 }

            selectedSha : Maybe String
            selectedSha =
                newModel.commits
                    |> List.drop newIndex
                    |> List.head
                    |> Maybe.map .sha
        in
        case selectedSha of
            Just sha ->
                ( { newModel | diffContent = "Loading..." }
                , Script.command "git" [ "show", "--stat", "-p", sha ]
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
                )

            Nothing ->
                ( newModel, Effect.none )


adjustScroll : Model -> Model
adjustScroll model =
    if model.selected < model.scrollOffset then
        { model | scrollOffset = model.selected }

    else if model.selected >= model.scrollOffset + 20 then
        { model | scrollOffset = model.selected - 19 }

    else
        model



-- VIEW


view : Tui.Context -> Model -> Tui.Screen
view ctx model =
    let
        leftWidth : Int
        leftWidth =
            min 40 (ctx.width // 3)

        rightWidth : Int
        rightWidth =
            ctx.width - leftWidth

        contentHeight : Int
        contentHeight =
            ctx.height - 2

        visibleCommits : List ( Int, Commit )
        visibleCommits =
            model.commits
                |> List.indexedMap Tuple.pair
                |> List.drop model.scrollOffset
                |> List.take (contentHeight - 2)

        -- Left pane: commit list
        leftLines : List String
        leftLines =
            visibleCommits
                |> List.map
                    (\( i, commit ) ->
                        let
                            prefix : String
                            prefix =
                                if i == model.selected then
                                    "▸ "

                                else
                                    "  "
                        in
                        prefix
                            ++ commit.sha
                            ++ " "
                            ++ truncate (leftWidth - String.length commit.sha - 5) commit.message
                    )

        -- Right pane: diff content
        diffLines : List String
        diffLines =
            model.diffContent
                |> String.lines
                |> List.drop model.diffScrollOffset
                |> List.take (contentHeight - 2)
    in
    drawLayout ctx
        { leftTitle = "Commits"
        , leftLines = leftLines
        , leftWidth = leftWidth
        , rightTitle = "Diff"
        , rightLines = diffLines
        , rightWidth = rightWidth
        , contentHeight = contentHeight
        , selectedIndex = model.selected - model.scrollOffset
        , statusLine = " j/k navigate  q quit  click/scroll"
        }


type alias LayoutConfig =
    { leftTitle : String
    , leftLines : List String
    , leftWidth : Int
    , rightTitle : String
    , rightLines : List String
    , rightWidth : Int
    , contentHeight : Int
    , selectedIndex : Int
    , statusLine : String
    }


drawLayout : Tui.Context -> LayoutConfig -> Tui.Screen
drawLayout ctx config =
    let
        dimStyle : Tui.Style
        dimStyle =
            { fg = Nothing, bg = Nothing, attributes = [ Tui.dim ] }

        borderStyle : Tui.Style
        borderStyle =
            { fg = Just Ansi.Color.blue, bg = Nothing, attributes = [] }

        titleStyle : Tui.Style
        titleStyle =
            { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [ Tui.bold ] }

        selectedStyle : Tui.Style
        selectedStyle =
            { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [ Tui.bold ] }

        addStyle : Tui.Style
        addStyle =
            { fg = Just Ansi.Color.green, bg = Nothing, attributes = [] }

        removeStyle : Tui.Style
        removeStyle =
            { fg = Just Ansi.Color.red, bg = Nothing, attributes = [] }

        innerLeftW : Int
        innerLeftW =
            config.leftWidth - 2

        innerRightW : Int
        innerRightW =
            config.rightWidth - 2

        -- Top border
        topBorder : Tui.Screen
        topBorder =
            Tui.concat
                [ Tui.styled borderStyle "┌"
                , Tui.styled titleStyle config.leftTitle
                , Tui.styled borderStyle
                    (String.repeat (innerLeftW - String.length config.leftTitle) "─")
                , Tui.styled borderStyle "┬"
                , Tui.styled titleStyle config.rightTitle
                , Tui.styled borderStyle
                    (String.repeat (innerRightW - String.length config.rightTitle) "─")
                , Tui.styled borderStyle "┐"
                ]

        -- Content rows
        contentRows : List Tui.Screen
        contentRows =
            List.range 0 (config.contentHeight - 3)
                |> List.map
                    (\i ->
                        let
                            leftContent : Tui.Screen
                            leftContent =
                                case config.leftLines |> List.drop i |> List.head of
                                    Just line ->
                                        if i == config.selectedIndex then
                                            Tui.styled selectedStyle
                                                (padRight innerLeftW line)

                                        else
                                            Tui.text (padRight innerLeftW line)

                                    Nothing ->
                                        Tui.text (String.repeat innerLeftW " ")

                            rightContent : Tui.Screen
                            rightContent =
                                case config.rightLines |> List.drop i |> List.head of
                                    Just line ->
                                        styleDiffLine innerRightW addStyle removeStyle dimStyle line

                                    Nothing ->
                                        Tui.text (String.repeat innerRightW " ")
                        in
                        Tui.concat
                            [ Tui.styled borderStyle "│"
                            , leftContent
                            , Tui.styled borderStyle "│"
                            , rightContent
                            , Tui.styled borderStyle "│"
                            ]
                    )

        -- Bottom border
        bottomBorder : Tui.Screen
        bottomBorder =
            Tui.concat
                [ Tui.styled borderStyle "└"
                , Tui.styled borderStyle (String.repeat innerLeftW "─")
                , Tui.styled borderStyle "┴"
                , Tui.styled borderStyle (String.repeat innerRightW "─")
                , Tui.styled borderStyle "┘"
                ]

        -- Status bar fills the full width
        statusBar : Tui.Screen
        statusBar =
            Tui.styled
                { fg = Just Ansi.Color.black
                , bg = Just Ansi.Color.white
                , attributes = []
                }
                (padRight ctx.width config.statusLine)
    in
    Tui.lines
        ([ topBorder ]
            ++ contentRows
            ++ [ bottomBorder
               , statusBar
               ]
        )


styleDiffLine : Int -> Tui.Style -> Tui.Style -> Tui.Style -> String -> Tui.Screen
styleDiffLine maxWidth addStyle removeStyle dimStyle line =
    let
        paddedLine : String
        paddedLine =
            padRight maxWidth (truncate maxWidth line)
    in
    if String.startsWith "+" line && not (String.startsWith "+++" line) then
        Tui.styled addStyle paddedLine

    else if String.startsWith "-" line && not (String.startsWith "---" line) then
        Tui.styled removeStyle paddedLine

    else if String.startsWith "@@" line then
        Tui.styled { fg = Just Ansi.Color.cyan, bg = Nothing, attributes = [] } paddedLine

    else if String.startsWith "commit " line || String.startsWith "Author:" line || String.startsWith "Date:" line then
        Tui.styled { fg = Just Ansi.Color.yellow, bg = Nothing, attributes = [] } paddedLine

    else
        Tui.styled dimStyle paddedLine


padRight : Int -> String -> String
padRight width str =
    let
        truncated : String
        truncated =
            if String.length str > width then
                String.left (width - 1) str ++ "…"

            else
                str
    in
    truncated ++ String.repeat (width - String.length truncated) " "


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
        , Tui.Sub.onMouse Mouse
        ]
