module Tui.Layout exposing
    ( Layout, Pane, horizontal, pane
    , Width, fill, fraction, px
    , Scroll, ScrollEvent, ScrollDirection(..), initScroll, scrollBy, scrollOffset
    , onScroll, onClick
    , toScreen, handleMouse
    )

{-| Split-pane layout with bordered panes, scrolling, and mouse dispatch.

Built on top of `Tui.Screen` primitives. Inspired by gocui's View system
but with Elm idioms — user owns scroll state in their Model, the package
handles rendering and mouse hit-testing.

    import Tui.Layout as Layout

    view ctx model =
        Layout.horizontal
            [ Layout.pane
                { title = "Commits"
                , width = Layout.fraction (1 / 3)
                , scroll = model.commitScroll
                }
                (commitListView model)
                |> Layout.onScroll CommitScroll
                |> Layout.onClick (\pos -> ClickedCommit pos.row)
            , Layout.pane
                { title = "Diff"
                , width = Layout.fill
                , scroll = model.diffScroll
                }
                (diffView model)
                |> Layout.onScroll DiffScroll
            ]
            |> Layout.toScreen { width = ctx.width, height = ctx.height }

@docs Layout, Pane, horizontal, pane

@docs Width, fill, fraction, px

@docs Scroll, ScrollEvent, ScrollDirection, initScroll, scrollBy, scrollOffset

@docs onScroll, onClick

@docs toScreen, handleMouse

-}

import Tui exposing (MouseEvent, Screen)


{-| A layout of panes.
-}
type Layout msg
    = Horizontal (List (Pane msg))


{-| A single pane in a layout.
-}
type Pane msg
    = Pane
        { title : String
        , width : Width
        , scroll : Scroll
        , content : Screen
        , onScrollHandler : Maybe (ScrollEvent -> msg)
        , onClickHandler : Maybe ({ row : Int, col : Int } -> msg)
        }


{-| Width specification for a pane.
-}
type Width
    = Fill
    | Fraction Float
    | Px Int


{-| Opaque scroll state. Maintain in your Model, update with `scrollBy`.
-}
type Scroll
    = Scroll { offset : Int }


{-| Scroll event data passed to `onScroll` handlers.
-}
type alias ScrollEvent =
    { direction : ScrollDirection
    , amount : Int
    }


{-| -}
type ScrollDirection
    = Up
    | Down



-- CONSTRUCTORS


{-| Create a horizontal split layout.
-}
horizontal : List (Pane msg) -> Layout msg
horizontal =
    Horizontal


{-| Create a pane with a title, width, scroll state, and content.
-}
pane :
    { title : String
    , width : Width
    , scroll : Scroll
    }
    -> Screen
    -> Pane msg
pane config content =
    Pane
        { title = config.title
        , width = config.width
        , scroll = config.scroll
        , content = content
        , onScrollHandler = Nothing
        , onClickHandler = Nothing
        }



-- WIDTH


{-| Fill remaining space.
-}
fill : Width
fill =
    Fill


{-| Fraction of available width (0.0 to 1.0).
-}
fraction : Float -> Width
fraction =
    Fraction


{-| Fixed pixel (column) width.
-}
px : Int -> Width
px =
    Px



-- SCROLL


{-| Initial scroll state (offset 0).
-}
initScroll : Scroll
initScroll =
    Scroll { offset = 0 }


{-| Adjust scroll by a delta. Positive = down, negative = up. Clamps at 0.
-}
scrollBy : Int -> Scroll -> Scroll
scrollBy delta (Scroll s) =
    Scroll { offset = max 0 (s.offset + delta) }


{-| Get the current scroll offset.
-}
scrollOffset : Scroll -> Int
scrollOffset (Scroll s) =
    s.offset



-- EVENT HANDLERS


{-| Attach a scroll handler to a pane. When the user scrolls over this pane,
your message receives the scroll direction and amount.
-}
onScroll : (ScrollEvent -> msg) -> Pane msg -> Pane msg
onScroll handler (Pane p) =
    Pane { p | onScrollHandler = Just handler }


{-| Attach a click handler to a pane. Coordinates are local to the pane content
(row 0 is the first content line, not the border).
-}
onClick : ({ row : Int, col : Int } -> msg) -> Pane msg -> Pane msg
onClick handler (Pane p) =
    Pane { p | onClickHandler = Just handler }



-- RENDERING


{-| Render the layout to a `Tui.Screen` at the given dimensions.
-}
toScreen : { width : Int, height : Int } -> Layout msg -> Screen
toScreen size (Horizontal panes) =
    let
        widths : List Int
        widths =
            resolveWidths size.width panes

        panesWithWidths : List ( Pane msg, Int )
        panesWithWidths =
            List.map2 Tuple.pair panes widths

        height : Int
        height =
            size.height
    in
    renderHorizontalPanes panesWithWidths height


renderHorizontalPanes : List ( Pane msg, Int ) -> Int -> Screen
renderHorizontalPanes panesWithWidths height =
    let
        paneCount : Int
        paneCount =
            List.length panesWithWidths

        renderRow : Int -> Screen
        renderRow row =
            Tui.concat
                (panesWithWidths
                    |> List.indexedMap
                        (\paneIndex ( Pane p, w ) ->
                            let
                                innerW : Int
                                innerW =
                                    if paneIndex == 0 then
                                        w - 2

                                    else
                                        w - 1

                                isFirstPane : Bool
                                isFirstPane =
                                    paneIndex == 0

                                isLastPane : Bool
                                isLastPane =
                                    paneIndex == paneCount - 1
                            in
                            if row == 0 then
                                -- Top border
                                Tui.concat
                                    [ Tui.text
                                        (if isFirstPane then
                                            "┌"

                                         else
                                            "┬"
                                        )
                                    , Tui.text p.title
                                    , Tui.text (String.repeat (innerW - String.length p.title) "─")
                                    , if isLastPane then
                                        Tui.text "┐"

                                      else
                                        Tui.empty
                                    ]

                            else if row == height - 1 then
                                -- Bottom border
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
                                -- Content row
                                let
                                    contentLines : List String
                                    contentLines =
                                        p.content
                                            |> Tui.toLines
                                            |> List.drop (scrollOffset p.scroll)

                                    contentRow : Int
                                    contentRow =
                                        row - 1

                                    lineText : String
                                    lineText =
                                        contentLines
                                            |> List.drop contentRow
                                            |> List.head
                                            |> Maybe.withDefault ""
                                            |> padAndTruncate innerW
                                in
                                Tui.concat
                                    [ Tui.text "│"
                                    , Tui.text lineText
                                    , if isLastPane then
                                        Tui.text "│"

                                      else
                                        Tui.empty
                                    ]
                        )
                )
    in
    List.range 0 (height - 1)
        |> List.map renderRow
        |> Tui.lines


resolveWidths : Int -> List (Pane msg) -> List Int
resolveWidths totalWidth panes =
    let
        fixed : List ( Bool, Maybe Int )
        fixed =
            panes
                |> List.map
                    (\(Pane p) ->
                        case p.width of
                            Px n ->
                                ( False, Just n )

                            Fraction f ->
                                ( False, Just (round (toFloat totalWidth * f)) )

                            Fill ->
                                ( True, Nothing )
                    )

        fillCount : Int
        fillCount =
            fixed
                |> List.filter (\( isFill, _ ) -> isFill)
                |> List.length

        fillWidth : Int
        fillWidth =
            if fillCount > 0 then
                let
                    fixedTotal : Int
                    fixedTotal =
                        fixed
                            |> List.filterMap Tuple.second
                            |> List.sum
                in
                (totalWidth - fixedTotal) // fillCount

            else
                0
    in
    fixed
        |> List.map
            (\( _, maybeW ) ->
                case maybeW of
                    Just w ->
                        w

                    Nothing ->
                        fillWidth
            )


padAndTruncate : Int -> String -> String
padAndTruncate width str =
    let
        truncated : String
        truncated =
            if String.length str > width then
                String.left (width - 1) str ++ "…"

            else
                str
    in
    truncated ++ String.repeat (width - String.length truncated) " "



-- MOUSE DISPATCH


{-| Dispatch a mouse event to the appropriate pane handler. Returns the
message if a handler matched, or Nothing if the event was outside all panes
or no handler was registered.

Coordinates are translated to pane-local: row 0 is the first content line
(below the top border), col 0 is the first content column (after the left
border).

-}
handleMouse : MouseEvent -> { width : Int, height : Int } -> Layout msg -> Maybe msg
handleMouse mouseEvent size (Horizontal panes) =
    let
        widths : List Int
        widths =
            resolveWidths size.width panes

        panesWithBounds : List { thePane : Pane msg, startCol : Int, endCol : Int }
        panesWithBounds =
            List.map2 Tuple.pair panes widths
                |> List.foldl
                    (\( p, w ) ( acc, col ) ->
                        ( acc ++ [ { thePane = p, startCol = col, endCol = col + w } ]
                        , col + w
                        )
                    )
                    ( [], 0 )
                |> Tuple.first
    in
    case mouseEvent of
        Tui.ScrollDown { col, amount } ->
            findPaneAt col panesWithBounds
                |> Maybe.andThen
                    (\{ thePane } ->
                        paneScrollHandler thePane
                            |> Maybe.map (\handler -> handler { direction = Down, amount = amount })
                    )

        Tui.ScrollUp { col, amount } ->
            findPaneAt col panesWithBounds
                |> Maybe.andThen
                    (\{ thePane } ->
                        paneScrollHandler thePane
                            |> Maybe.map (\handler -> handler { direction = Up, amount = amount })
                    )

        Tui.Click { row, col } ->
            findPaneAt col panesWithBounds
                |> Maybe.andThen
                    (\{ thePane, startCol } ->
                        paneClickHandler thePane
                            |> Maybe.map
                                (\handler ->
                                    handler
                                        { row = row - 1
                                        , col = col - startCol - 1
                                        }
                                )
                    )


findPaneAt : Int -> List { thePane : Pane msg, startCol : Int, endCol : Int } -> Maybe { thePane : Pane msg, startCol : Int, endCol : Int }
findPaneAt col panesWithBounds =
    panesWithBounds
        |> List.filter (\{ startCol, endCol } -> col >= startCol && col < endCol)
        |> List.head


paneScrollHandler : Pane msg -> Maybe (ScrollEvent -> msg)
paneScrollHandler (Pane p) =
    p.onScrollHandler


paneClickHandler : Pane msg -> Maybe ({ row : Int, col : Int } -> msg)
paneClickHandler (Pane p) =
    p.onClickHandler
