module Tui.Layout exposing
    ( Layout, Pane, horizontal, pane
    , PaneContent, content, selectableList
    , Width, fill, fillPortion, px
    , State, init, withContext
    , navigateDown, navigateUp, selectedIndex, scrollPosition, resetScroll, contextOf
    , handleMouse
    , toScreen
    )

{-| Split-pane layout with opaque state, selectable lists, and mouse dispatch.

Inspired by gocui/Ratatui. The framework tracks scroll offsets, selection
indices, and terminal dimensions in an opaque `State`. The user stores one
`State` field in their Model.

    import Tui.Layout as Layout

    type alias Model =
        { layout : Layout.State
        , commits : List Commit
        }

    view ctx model =
        Layout.horizontal
            [ Layout.pane "commits"
                { title = "Commits", width = Layout.fill }
                (Layout.selectableList
                    { onSelect = SelectCommit
                    , selected = \c -> Tui.text ("▸ " ++ c.sha)
                    , default = \c -> Tui.text ("  " ++ c.sha)
                    }
                    model.commits
                )
            ]
            |> Layout.toScreen (Layout.withContext ctx model.layout)

@docs Layout, Pane, horizontal, pane

@docs PaneContent, content, selectableList

@docs Width, fill, fillPortion, px

@docs State, init, withContext

@docs navigateDown, navigateUp, selectedIndex, scrollPosition, resetScroll, contextOf

@docs handleMouse

@docs toScreen

-}

import Dict exposing (Dict)
import Tui exposing (MouseEvent, Screen)


{-| A layout of panes.
-}
type Layout msg
    = Horizontal (List (PaneConfig msg))


type alias PaneConfig msg =
    { id : String
    , title : String
    , width : Width
    , paneContent : PaneContent msg
    }


{-| A pane in a layout (opaque).
-}
type Pane msg
    = PaneConstructor (PaneConfig msg)


{-| Content for a pane — either a static list of screens or a selectable list.
-}
type PaneContent msg
    = StaticContent (List Screen)
    | SelectableContent
        { items : List ( Screen, Screen )
        , onSelect : Int -> msg
        }


{-| Width specification using integer weights (like elm-ui).
-}
type Width
    = Fill Int
    | Px Int


{-| Opaque state tracking scroll offsets, selection indices, and terminal
dimensions for all panes. Store ONE of these in your Model.
-}
type State
    = State
        { paneStates : Dict String PaneState
        , context : { width : Int, height : Int }
        }


type alias PaneState =
    { scrollOffset : Int
    , selectedIndex : Int
    }



-- CONSTRUCTORS


{-| Create a horizontal split layout.
-}
horizontal : List (Pane msg) -> Layout msg
horizontal panes =
    Horizontal (List.map (\(PaneConstructor config) -> config) panes)


{-| Create a pane.

    Layout.pane "commits"
        { title = "Commits", width = Layout.fill }
        (Layout.selectableList { ... } items)

-}
pane : String -> { title : String, width : Width } -> PaneContent msg -> Pane msg
pane id config paneContent =
    PaneConstructor
        { id = id
        , title = config.title
        , width = config.width
        , paneContent = paneContent
        }


{-| Static content — a list of screens, one per line. No selection behavior.
-}
content : List Screen -> PaneContent msg
content =
    StaticContent


{-| A selectable list. The framework tracks which item is selected and renders
the appropriate variant. Handles click-to-select and keyboard navigation.

    Layout.selectableList
        { onSelect = SelectCommit
        , selected = \commit -> Tui.styled selectedStyle commit.sha
        , default = \commit -> Tui.text commit.sha
        }
        model.commits

-}
selectableList :
    { onSelect : Int -> msg
    , selected : item -> Screen
    , default : item -> Screen
    }
    -> List item
    -> PaneContent msg
selectableList config items =
    SelectableContent
        { items =
            items
                |> List.map
                    (\item ->
                        ( config.default item, config.selected item )
                    )
        , onSelect = config.onSelect
        }



-- WIDTH


{-| Fill remaining space with weight 1.
-}
fill : Width
fill =
    Fill 1


{-| Fill remaining space with a weight. Two panes with `fillPortion 2` and
`fillPortion 1` split space 2:1, matching elm-ui's `fillPortion`.
-}
fillPortion : Int -> Width
fillPortion =
    Fill


{-| Fixed column width.
-}
px : Int -> Width
px =
    Px



-- STATE


{-| Initial empty state.
-}
init : State
init =
    State
        { paneStates = Dict.empty
        , context = { width = 80, height = 24 }
        }


{-| Update the terminal dimensions in the state. Call this with the `Context`
from your `view` function.
-}
withContext : { width : Int, height : Int } -> State -> State
withContext ctx (State s) =
    State { s | context = ctx }


{-| Move selection down in a pane.
-}
navigateDown : String -> State -> State
navigateDown paneId (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert paneId
                    { ps | selectedIndex = ps.selectedIndex + 1 }
                    s.paneStates
        }


{-| Move selection up in a pane.
-}
navigateUp : String -> State -> State
navigateUp paneId (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert paneId
                    { ps | selectedIndex = max 0 (ps.selectedIndex - 1) }
                    s.paneStates
        }


{-| Get the currently selected index for a pane.
-}
selectedIndex : String -> State -> Int
selectedIndex paneId (State s) =
    Dict.get paneId s.paneStates
        |> Maybe.map .selectedIndex
        |> Maybe.withDefault 0


{-| Get the current scroll position for a pane.
-}
scrollPosition : String -> State -> Int
scrollPosition paneId (State s) =
    Dict.get paneId s.paneStates
        |> Maybe.map .scrollOffset
        |> Maybe.withDefault 0


{-| Reset scroll position for a pane to 0. Call when loading new content
(e.g., reset the diff scroll when selecting a different commit).
-}
resetScroll : String -> State -> State
resetScroll paneId (State s) =
    let
        ps : PaneState
        ps =
            Dict.get paneId s.paneStates
                |> Maybe.withDefault defaultPaneState
    in
    State
        { s
            | paneStates =
                Dict.insert paneId
                    { ps | scrollOffset = 0 }
                    s.paneStates
        }


{-| Get the context stored in the state. Useful for passing to `handleMouse`
when `update` doesn't receive `Context` directly.
-}
contextOf : State -> { width : Int, height : Int }
contextOf (State s) =
    s.context


defaultPaneState : PaneState
defaultPaneState =
    { scrollOffset = 0, selectedIndex = 0 }



-- MOUSE DISPATCH


{-| Handle a mouse event. Updates internal state (scroll, selection) and
returns the updated state plus an optional user message from click handlers.
Pass the terminal context for correct pane hit-testing.
-}
handleMouse : MouseEvent -> { width : Int, height : Int } -> Layout msg -> State -> ( State, Maybe msg )
handleMouse mouseEvent ctx (Horizontal panes) (State s) =
    let
        -- Persist context so contextOf returns correct values next time
        sWithCtx :
            { paneStates : Dict String PaneState
            , context : { width : Int, height : Int }
            }
        sWithCtx =
            { s | context = ctx }

        widths : List Int
        widths =
            resolveWidths ctx.width (List.map .width panes)

        panesWithBounds : List { config : PaneConfig msg, startCol : Int, endCol : Int }
        panesWithBounds =
            List.map2 Tuple.pair panes widths
                |> List.foldl
                    (\( paneConfig, w ) ( acc, col ) ->
                        ( acc ++ [ { config = paneConfig, startCol = col, endCol = col + w } ]
                        , col + w
                        )
                    )
                    ( [], 0 )
                |> Tuple.first
    in
    case mouseEvent of
        Tui.ScrollDown { col, amount } ->
            case findPaneAt col panesWithBounds of
                Just { config } ->
                    let
                        ps : PaneState
                        ps =
                            Dict.get config.id sWithCtx.paneStates
                                |> Maybe.withDefault defaultPaneState

                        delta : Int
                        delta =
                            amount * 3
                    in
                    ( State
                        { sWithCtx
                            | paneStates =
                                Dict.insert config.id
                                    { ps | scrollOffset = ps.scrollOffset + delta }
                                    sWithCtx.paneStates
                        }
                    , Nothing
                    )

                Nothing ->
                    ( State sWithCtx, Nothing )

        Tui.ScrollUp { col, amount } ->
            case findPaneAt col panesWithBounds of
                Just { config } ->
                    let
                        ps : PaneState
                        ps =
                            Dict.get config.id sWithCtx.paneStates
                                |> Maybe.withDefault defaultPaneState

                        delta : Int
                        delta =
                            amount * 3
                    in
                    ( State
                        { sWithCtx
                            | paneStates =
                                Dict.insert config.id
                                    { ps | scrollOffset = max 0 (ps.scrollOffset - delta) }
                                    sWithCtx.paneStates
                        }
                    , Nothing
                    )

                Nothing ->
                    ( State sWithCtx, Nothing )

        Tui.Click { row, col } ->
            case findPaneAt col panesWithBounds of
                Just { config } ->
                    case config.paneContent of
                        SelectableContent { onSelect } ->
                            let
                                contentRow : Int
                                contentRow =
                                    row - 1

                                ps : PaneState
                                ps =
                                    Dict.get config.id sWithCtx.paneStates
                                        |> Maybe.withDefault defaultPaneState

                                clickedIndex : Int
                                clickedIndex =
                                    contentRow + ps.scrollOffset
                            in
                            ( State
                                { s
                                    | paneStates =
                                        Dict.insert config.id
                                            { ps | selectedIndex = clickedIndex }
                                            sWithCtx.paneStates
                                }
                            , Just (onSelect clickedIndex)
                            )

                        StaticContent _ ->
                            ( State sWithCtx, Nothing )

                Nothing ->
                    ( State sWithCtx, Nothing )


findPaneAt : Int -> List { config : PaneConfig msg, startCol : Int, endCol : Int } -> Maybe { config : PaneConfig msg, startCol : Int, endCol : Int }
findPaneAt col panesWithBounds =
    panesWithBounds
        |> List.filter (\{ startCol, endCol } -> col >= startCol && col < endCol)
        |> List.head



-- RENDERING


{-| Render the layout to a Screen using the given state.
-}
toScreen : State -> Layout msg -> Screen
toScreen (State s) (Horizontal panes) =
    let
        totalWidth : Int
        totalWidth =
            s.context.width

        totalHeight : Int
        totalHeight =
            s.context.height

        widths : List Int
        widths =
            resolveWidths totalWidth (List.map .width panes)

        panesWithWidths : List ( PaneConfig msg, Int )
        panesWithWidths =
            List.map2 Tuple.pair panes widths

        paneCount : Int
        paneCount =
            List.length panes

        renderRow : Int -> Screen
        renderRow row =
            Tui.concat
                (panesWithWidths
                    |> List.indexedMap
                        (\paneIdx ( paneConfig, w ) ->
                            let
                                innerW : Int
                                innerW =
                                    if paneIdx == 0 then
                                        w - 2

                                    else
                                        w - 1

                                isFirstPane : Bool
                                isFirstPane =
                                    paneIdx == 0

                                isLastPane : Bool
                                isLastPane =
                                    paneIdx == paneCount - 1
                            in
                            if row == 0 then
                                Tui.concat
                                    [ Tui.text
                                        (if isFirstPane then
                                            "┌"

                                         else
                                            "┬"
                                        )
                                    , Tui.text paneConfig.title
                                    , Tui.text (String.repeat (max 0 (innerW - String.length paneConfig.title)) "─")
                                    , if isLastPane then
                                        Tui.text "┐"

                                      else
                                        Tui.empty
                                    ]

                            else if row == totalHeight - 1 then
                                Tui.concat
                                    [ Tui.text
                                        (if isFirstPane then
                                            "└"

                                         else
                                            "┴"
                                        )
                                    , Tui.text (String.repeat innerW "─")
                                    , if isLastPane then
                                        Tui.text "┘"

                                      else
                                        Tui.empty
                                    ]

                            else
                                let
                                    ps : PaneState
                                    ps =
                                        Dict.get paneConfig.id s.paneStates
                                            |> Maybe.withDefault defaultPaneState

                                    contentRow : Int
                                    contentRow =
                                        row - 1

                                    lineScreen : Screen
                                    lineScreen =
                                        getContentLine paneConfig ps contentRow

                                    lineText : String
                                    lineText =
                                        Tui.toString lineScreen

                                    lineWidth : Int
                                    lineWidth =
                                        String.length lineText

                                    truncatedLine : Screen
                                    truncatedLine =
                                        Tui.truncateWidth innerW lineScreen

                                    actualWidth : Int
                                    actualWidth =
                                        min lineWidth innerW

                                    padding : Int
                                    padding =
                                        max 0 (innerW - actualWidth)
                                in
                                Tui.concat
                                    [ Tui.text "│"
                                    , truncatedLine
                                    , Tui.text (String.repeat padding " ")
                                    , if isLastPane then
                                        Tui.text "│"

                                      else
                                        Tui.empty
                                    ]
                        )
                )
    in
    List.range 0 (totalHeight - 1)
        |> List.map renderRow
        |> Tui.lines


getContentLine : PaneConfig msg -> PaneState -> Int -> Screen
getContentLine paneConfig ps contentRow =
    let
        scrolledRow : Int
        scrolledRow =
            contentRow + ps.scrollOffset
    in
    case paneConfig.paneContent of
        StaticContent lines ->
            lines
                |> List.drop scrolledRow
                |> List.head
                |> Maybe.withDefault Tui.empty

        SelectableContent { items } ->
            items
                |> List.indexedMap
                    (\i ( defaultView, selectedView ) ->
                        if i == ps.selectedIndex then
                            selectedView

                        else
                            defaultView
                    )
                |> List.drop scrolledRow
                |> List.head
                |> Maybe.withDefault Tui.empty


resolveWidths : Int -> List Width -> List Int
resolveWidths totalWidth widthSpecs =
    let
        fixedTotal : Int
        fixedTotal =
            widthSpecs
                |> List.filterMap
                    (\w ->
                        case w of
                            Px n ->
                                Just n

                            Fill _ ->
                                Nothing
                    )
                |> List.sum

        totalWeight : Int
        totalWeight =
            widthSpecs
                |> List.filterMap
                    (\w ->
                        case w of
                            Fill weight ->
                                Just weight

                            Px _ ->
                                Nothing
                    )
                |> List.sum

        remaining : Int
        remaining =
            totalWidth - fixedTotal
    in
    widthSpecs
        |> List.map
            (\w ->
                case w of
                    Px n ->
                        n

                    Fill weight ->
                        if totalWeight > 0 then
                            (remaining * weight) // totalWeight

                        else
                            0
            )
