module CompileAppTests exposing (suite)

import Ansi.Color
import BackendTask
import Expect
import Test exposing (Test, describe, test)
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Event
import Tui.Layout as Layout
import Tui.Menu as Menu
import Tui.Screen
import Tui.Test as TuiTest


suite : Test
suite =
    describe "Layout.compileApp"
        [ describe "clickText"
            [ test "clickText finds text in second pane correctly" <|
                \() ->
                    linkAppTest
                        |> TuiTest.clickText "plain text"
                        -- The second pane has "plain text" — clicking it should
                        -- NOT select an item in the first pane (the bug was col=1
                        -- always hitting the first pane)
                        |> TuiTest.ensureViewHas "clicked: none"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "withOnLinkClick"
            [ test "fires callback with URL when clicking linked text" <|
                \() ->
                    linkAppTest
                        |> TuiTest.clickText "Click me"
                        |> TuiTest.ensureViewHas "clicked: https://example.com"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "does NOT fire when clicking non-linked text" <|
                \() ->
                    linkAppTest
                        |> TuiTest.clickText "plain text"
                        |> TuiTest.ensureViewHas "clicked: none"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "on selectable pane: link click fires link callback without changing selection" <|
                \() ->
                    linkSelectableAppTest
                        -- Initially auto-selects index 0 (linked-item)
                        |> TuiTest.ensureViewHas "selected: linked-item"
                        -- Navigate to plain-item first so we can observe selection doesn't change
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "selected: plain-item"
                        -- Now click on the linked text — should fire link callback, NOT change selection
                        |> TuiTest.clickText "linked-item"
                        |> TuiTest.ensureViewHas "link: https://item.example"
                        |> TuiTest.ensureViewHas "selected: plain-item"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "on selectable pane: non-link click fires onSelect" <|
                \() ->
                    linkSelectableAppTest
                        |> TuiTest.clickText "plain-item"
                        |> TuiTest.ensureViewHas "link: none"
                        |> TuiTest.ensureViewHas "selected: plain-item"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "Bottom border"
            [ test "compileApp renders bottom border with ╰ and ╯" <|
                \() ->
                    linkAppTest
                        |> TuiTest.ensureViewHas "╰"
                        |> TuiTest.ensureViewHas "╯"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "j/k scrolls content panes"
            [ test "j scrolls content pane down when focused" <|
                \() ->
                    scrollAppTest
                        -- docs pane is auto-focused, has Line 1..50
                        |> TuiTest.ensureViewHas "scroll: 0"
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        -- Scroll position should have changed
                        |> TuiTest.ensureViewHas "scroll: 3"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "k scrolls content pane up after scrolling down" <|
                \() ->
                    scrollAppTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "scroll: 3"
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'k'
                        |> TuiTest.pressKey 'k'
                        -- Should be back to 0
                        |> TuiTest.ensureViewHas "scroll: 0"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "Effect.setSelectedIndex auto-scrolls"
            [ test "setSelectedIndex scrolls pane to keep selection visible" <|
                \() ->
                    -- Use a short terminal so only ~5 items are visible (height 8 = 1 top + 5 content + 1 bottom + 1 bar)
                    setSelAppTest
                        |> TuiTest.ensureViewHas "item-A"
                        -- item-H should be off-screen initially
                        |> TuiTest.ensureViewDoesNotHave "item-H"
                        -- Press 'd' which triggers Effect.setSelectedIndex "items" 7 (item-H)
                        |> TuiTest.pressKey 'd'
                        -- After setSelectedIndex, the pane should have scrolled to show item-H
                        |> TuiTest.ensureViewHas "item-H"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "setSelectedIndex to middle item scrolls correctly with many items below" <|
                \() ->
                    -- 'e' triggers Effect.setSelectedIndex "items" 5 (item-F, index 5)
                    -- With 5 visible rows (height 8), items A-E are visible (indices 0-4)
                    -- Index 5 is below fold, pane should scroll to show it
                    setSelAppTest
                        |> TuiTest.ensureViewHas "item-A"
                        |> TuiTest.ensureViewDoesNotHave "item-F"
                        |> TuiTest.pressKey 'e'
                        |> TuiTest.ensureViewHas "item-F"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "j/k keeps selection visible at bottom of long list"
            [ test "navigating to last item with j keeps it visible" <|
                \() ->
                    -- setSelAppTest has 8 items, height 8 = 5 visible content rows
                    -- Press j 7 times to reach the last item (item-H, index 7)
                    setSelAppTest
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        -- After 7 j presses, selection is at index 7 (item-H)
                        -- The pane must have scrolled so item-H is visible
                        |> TuiTest.ensureViewHas "item-H"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "withOnScroll"
            [ test "scroll callback fires when mouse wheel scrolls a pane" <|
                \() ->
                    scrollAppTest
                        |> TuiTest.ensureViewHas "scroll: 0"
                        |> TuiTest.scrollDown { row = 1, col = 1 }
                        |> TuiTest.ensureViewDoesNotHave "scroll: 0"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "Help modal"
            [ test "Esc closes help modal and stays closed on next j press" <|
                \() ->
                    helpAppTest
                        -- Open help with '?'
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Keybindings"
                        -- Esc should close it
                        |> TuiTest.pressKeyWith { key = Tui.Event.Escape, modifiers = [] }
                        |> TuiTest.ensureViewDoesNotHave "Keybindings"
                        -- j should NOT re-open the help modal
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewDoesNotHave "Keybindings"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "j/k scrolls through ALL help items including built-in navigation" <|
                \() ->
                    helpAppTest
                        -- Open help
                        |> TuiTest.pressKey '?'
                        |> TuiTest.ensureViewHas "Keybindings"
                        -- Should see both built-in nav and user bindings
                        |> TuiTest.ensureViewHas "Navigate down"
                        |> TuiTest.ensureViewHas "Do thing"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "pressing j in help modal scrolls content without shrinking the modal" <|
                \() ->
                    let
                        -- Use a tall terminal so all help content fits inside
                        -- the modal (no clamping). This makes the List.drop
                        -- shrinking bug visible — the modal shrinks as rows
                        -- are dropped instead of maintaining its height.
                        shortTerminal =
                            helpAppTestWithContext
                                { width = 80, height = 40, colorProfile = Tui.TrueColor }

                        snapshots =
                            shortTerminal
                                |> TuiTest.pressKey '?'
                                |> TuiTest.pressKey 'j'
                                |> TuiTest.pressKey 'j'
                                |> TuiTest.pressKey 'j'
                                |> TuiTest.pressKey 'j'
                                |> TuiTest.toSnapshots

                        -- Get modal heights, skipping snapshots before the modal is open
                        snapshotHeights =
                            snapshots
                                |> List.map (\s -> modalHeight (Tui.Screen.toString s.screen))
                                |> List.filter (\h -> h > 0)

                        allSame =
                            case snapshotHeights of
                                first :: rest ->
                                    List.all (\h -> h == first) rest

                                [] ->
                                    False
                    in
                    if List.isEmpty snapshotHeights then
                        Expect.fail "No modal snapshots found — help modal never opened"

                    else if not allSame then
                        Expect.fail
                            ("Modal height changed while scrolling with j. "
                                ++ "Heights across snapshots: "
                                ++ String.join ", " (List.map String.fromInt snapshotHeights)
                                ++ ". Expected all heights to be equal."
                            )

                    else
                        Expect.pass
            ]
        , describe "Picker modal"
            [ test "j keeps the selected item visible in long picker lists" <|
                \() ->
                    pickerAppTest
                        |> TuiTest.pressKey 'p'
                        |> TuiTest.ensureViewHas "Pick item"
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "▸ Item 09"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "Menu modal"
            [ test "j keeps the highlighted action visible in long menus" <|
                \() ->
                    menuAppTest
                        |> TuiTest.pressKey 'm'
                        |> TuiTest.ensureViewHas "Menu"
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.pressKey 'j'
                        |> TuiTest.ensureViewHas "Item 09"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        ]


{-| Count the height of the modal overlay. Modal lines are nested inside the
pane border, so they start with `│╭` (top), `││` (body), or `│╰` (bottom).
-}
modalHeight : String -> Int
modalHeight screenText =
    screenText
        |> String.lines
        |> List.map String.trimLeft
        |> List.filter
            (\line ->
                String.startsWith "│╭" line
                    || String.startsWith "││" line
                    || String.startsWith "│╰" line
            )
        |> List.length



-- Test app with help modal


type alias HelpModel =
    { items : List String
    , selected : String
    , modal : Maybe ModalKind
    }


type ModalKind
    = HelpView


type HelpMsg
    = SelectItem String
    | OpenHelp
    | CloseModal
    | DoThing


helpInit : () -> ( HelpModel, Effect HelpMsg )
helpInit () =
    ( { items = [ "alpha", "beta", "gamma" ]
      , selected = ""
      , modal = Nothing
      }
    , Effect.none
    )


helpUpdate : Layout.UpdateContext -> HelpMsg -> HelpModel -> ( HelpModel, Effect HelpMsg )
helpUpdate _ msg model =
    case msg of
        SelectItem item ->
            ( { model | selected = item }, Effect.none )

        OpenHelp ->
            ( { model | modal = Just HelpView }, Effect.none )

        CloseModal ->
            ( { model | modal = Nothing }, Effect.none )

        DoThing ->
            ( model, Effect.none )


helpView : Tui.Context -> HelpModel -> Layout.Layout HelpMsg
helpView _ model =
    Layout.horizontal
        [ Layout.pane "items"
            { title = "Items", width = Layout.fill }
            (Layout.selectableList
                { onSelect = SelectItem
                , view =
                    \{ selection } item ->
                        case selection of
                            Layout.Selected { focused } ->
                                Tui.Screen.text ("▸ " ++ item)
                                    |> (if focused then
                                            Tui.Screen.bg Ansi.Color.blue

                                        else
                                            Tui.Screen.bold
                                       )

                            Layout.NotSelected ->
                                Tui.Screen.text ("  " ++ item)
                }
                model.items
            )
        ]


helpBindings : { focusedPane : Maybe String } -> HelpModel -> List (Layout.Group HelpMsg)
helpBindings _ _ =
    [ Layout.group "Actions"
        [ Layout.charBinding '?' "Help" OpenHelp
        , Layout.charBinding 'x' "Do thing" DoThing
        ]
    ]


helpStatus : HelpModel -> { waiting : Maybe String }
helpStatus _ =
    { waiting = Nothing }


helpModal : HelpModel -> Maybe (Layout.Modal HelpMsg)
helpModal model =
    case model.modal of
        Just HelpView ->
            Just (Layout.helpModal CloseModal)

        Nothing ->
            Nothing


helpAppConfig =
    Layout.compileApp
        { data = BackendTask.succeed ()
        , init = helpInit
        , update = helpUpdate
        , view = helpView
        , bindings = helpBindings
        , status = helpStatus
        , modal = helpModal
        , onRawEvent = Nothing
        }


helpAppTestWithContext : Tui.Context -> TuiTest.TuiTest (Layout.FrameworkModel HelpModel HelpMsg) (Layout.FrameworkMsg HelpMsg)
helpAppTestWithContext ctx =
    TuiTest.startAppWithContext ctx () helpAppConfig


helpAppTest : TuiTest.TuiTest (Layout.FrameworkModel HelpModel HelpMsg) (Layout.FrameworkMsg HelpMsg)
helpAppTest =
    TuiTest.startApp () helpAppConfig



-- Picker modal test app


type alias PickerModel =
    { modalOpen : Bool
    , selected : Maybe String
    }


type PickerMsg
    = OpenPicker
    | CancelPicker
    | PickItem String


pickerItems : List String
pickerItems =
    List.range 1 12
        |> List.map (\i -> "Item " ++ String.padLeft 2 '0' (String.fromInt i))


pickerInit : () -> ( PickerModel, Effect PickerMsg )
pickerInit () =
    ( { modalOpen = False, selected = Nothing }, Effect.none )


pickerUpdate : Layout.UpdateContext -> PickerMsg -> PickerModel -> ( PickerModel, Effect PickerMsg )
pickerUpdate _ msg model =
    case msg of
        OpenPicker ->
            ( { model | modalOpen = True }, Effect.none )

        CancelPicker ->
            ( { model | modalOpen = False }, Effect.none )

        PickItem item ->
            ( { model | modalOpen = False, selected = Just item }, Effect.none )


pickerView : Tui.Context -> PickerModel -> Layout.Layout PickerMsg
pickerView _ model =
    Layout.horizontal
        [ Layout.pane "status"
            { title = "Status", width = Layout.fill }
            (Layout.content
                [ Tui.Screen.text ("selected: " ++ Maybe.withDefault "none" model.selected)
                , Tui.Screen.text "press p to open picker"
                ]
            )
        ]


pickerBindings : { focusedPane : Maybe String } -> PickerModel -> List (Layout.Group PickerMsg)
pickerBindings _ _ =
    [ Layout.group "Actions"
        [ Layout.charBinding 'p' "Open picker" OpenPicker
        ]
    ]


pickerStatus : PickerModel -> { waiting : Maybe String }
pickerStatus _ =
    { waiting = Nothing }


pickerModal : PickerModel -> Maybe (Layout.Modal PickerMsg)
pickerModal model =
    if model.modalOpen then
        Just
            (Layout.pickerModal
                { items = pickerItems
                , toString = identity
                , title = "Pick item"
                , onSelect = PickItem
                , onCancel = CancelPicker
                }
            )

    else
        Nothing


pickerAppConfig =
    Layout.compileApp
        { data = BackendTask.succeed ()
        , init = pickerInit
        , update = pickerUpdate
        , view = pickerView
        , bindings = pickerBindings
        , status = pickerStatus
        , modal = pickerModal
        , onRawEvent = Nothing
        }


pickerAppTest : TuiTest.TuiTest (Layout.FrameworkModel PickerModel PickerMsg) (Layout.FrameworkMsg PickerMsg)
pickerAppTest =
    TuiTest.startAppWithContext { width = 40, height = 12, colorProfile = Tui.TrueColor } () pickerAppConfig



-- Menu modal test app


type alias MenuModel =
    { modalOpen : Bool
    }


type MenuMsg
    = OpenMenu
    | ChooseMenuItem String


menuItems : List (Menu.Item MenuMsg)
menuItems =
    List.range 1 12
        |> List.map
            (\i ->
                let
                    label =
                        "Item " ++ String.padLeft 2 '0' (String.fromInt i)

                    keyChar =
                        Char.fromCode (Char.toCode 'a' + i - 1)
                in
                Menu.item
                    { key = Tui.Event.Character keyChar
                    , label = label
                    , action = ChooseMenuItem label
                    }
            )


menuInit : () -> ( MenuModel, Effect MenuMsg )
menuInit () =
    ( { modalOpen = False }, Effect.none )


menuUpdate : Layout.UpdateContext -> MenuMsg -> MenuModel -> ( MenuModel, Effect MenuMsg )
menuUpdate _ msg model =
    case msg of
        OpenMenu ->
            ( { model | modalOpen = True }, Effect.none )

        ChooseMenuItem _ ->
            ( { model | modalOpen = False }, Effect.none )


menuView : Tui.Context -> MenuModel -> Layout.Layout MenuMsg
menuView _ _ =
    Layout.horizontal
        [ Layout.pane "status"
            { title = "Status", width = Layout.fill }
            (Layout.content
                [ Tui.Screen.text "press m to open menu"
                ]
            )
        ]


menuBindings : { focusedPane : Maybe String } -> MenuModel -> List (Layout.Group MenuMsg)
menuBindings _ _ =
    [ Layout.group "Actions"
        [ Layout.charBinding 'm' "Open menu" OpenMenu
        ]
    ]


menuStatus : MenuModel -> { waiting : Maybe String }
menuStatus _ =
    { waiting = Nothing }


menuModal : MenuModel -> Maybe (Layout.Modal MenuMsg)
menuModal model =
    if model.modalOpen then
        Just
            (Layout.menuModal
                [ Menu.section "Actions" menuItems
                ]
            )

    else
        Nothing


menuAppConfig =
    Layout.compileApp
        { data = BackendTask.succeed ()
        , init = menuInit
        , update = menuUpdate
        , view = menuView
        , bindings = menuBindings
        , status = menuStatus
        , modal = menuModal
        , onRawEvent = Nothing
        }


menuAppTest : TuiTest.TuiTest (Layout.FrameworkModel MenuModel MenuMsg) (Layout.FrameworkMsg MenuMsg)
menuAppTest =
    TuiTest.startAppWithContext { width = 40, height = 12, colorProfile = Tui.TrueColor } () menuAppConfig



-- Link click test app (static content with hyperlinks in second pane)


type alias LinkModel =
    { clickedUrl : Maybe String
    }


type LinkMsg
    = LinkClicked String
    | NoOp


linkInit : () -> ( LinkModel, Effect LinkMsg )
linkInit () =
    ( { clickedUrl = Nothing }, Effect.none )


linkUpdate : Layout.UpdateContext -> LinkMsg -> LinkModel -> ( LinkModel, Effect LinkMsg )
linkUpdate _ msg model =
    case msg of
        LinkClicked url ->
            ( { model | clickedUrl = Just url }, Effect.none )

        NoOp ->
            ( model, Effect.none )


linkView : Tui.Context -> LinkModel -> Layout.Layout LinkMsg
linkView _ model =
    Layout.horizontal
        [ Layout.pane "left"
            { title = "Left", width = Layout.fill }
            (Layout.content
                [ Tui.Screen.text "left pane content"
                ]
            )
        , Layout.pane "right"
            { title = "Right", width = Layout.fill }
            (Layout.content
                [ Tui.Screen.concat
                    [ Tui.Screen.text "Click me" |> Tui.Screen.link { url = "https://example.com" }
                    , Tui.Screen.text " and "
                    , Tui.Screen.text "plain text"
                    ]
                , Tui.Screen.text ("clicked: " ++ Maybe.withDefault "none" model.clickedUrl)
                ]
            )
            |> Layout.withOnLinkClick LinkClicked
        ]


linkBindings : { focusedPane : Maybe String } -> LinkModel -> List (Layout.Group LinkMsg)
linkBindings _ _ =
    []


linkStatus : LinkModel -> { waiting : Maybe String }
linkStatus _ =
    { waiting = Nothing }


linkModal : LinkModel -> Maybe (Layout.Modal LinkMsg)
linkModal _ =
    Nothing


linkAppConfig =
    Layout.compileApp
        { data = BackendTask.succeed ()
        , init = linkInit
        , update = linkUpdate
        , view = linkView
        , bindings = linkBindings
        , status = linkStatus
        , modal = linkModal
        , onRawEvent = Nothing
        }


linkAppTest : TuiTest.TuiTest (Layout.FrameworkModel LinkModel LinkMsg) (Layout.FrameworkMsg LinkMsg)
linkAppTest =
    TuiTest.startApp () linkAppConfig



-- Link click + selectable test app


type alias LinkSelModel =
    { clickedUrl : Maybe String
    , selectedItem : Maybe String
    , items : List String
    }


type LinkSelMsg
    = LinkSelLinkClicked String
    | LinkSelSelected String


linkSelInit : () -> ( LinkSelModel, Effect LinkSelMsg )
linkSelInit () =
    ( { clickedUrl = Nothing
      , selectedItem = Nothing
      , items = [ "linked-item", "plain-item" ]
      }
    , Effect.none
    )


linkSelUpdate : Layout.UpdateContext -> LinkSelMsg -> LinkSelModel -> ( LinkSelModel, Effect LinkSelMsg )
linkSelUpdate _ msg model =
    case msg of
        LinkSelLinkClicked url ->
            ( { model | clickedUrl = Just url }, Effect.none )

        LinkSelSelected item ->
            ( { model | selectedItem = Just item }, Effect.none )


linkSelView : Tui.Context -> LinkSelModel -> Layout.Layout LinkSelMsg
linkSelView _ model =
    Layout.horizontal
        [ Layout.pane "items"
            { title = "Items", width = Layout.fill }
            (Layout.selectableList
                { onSelect = LinkSelSelected
                , view =
                    \{ selection } item ->
                        let
                            prefix =
                                case selection of
                                    Layout.Selected _ ->
                                        "▸ "

                                    Layout.NotSelected ->
                                        "  "
                        in
                        if item == "linked-item" then
                            Tui.Screen.concat
                                [ Tui.Screen.text prefix
                                , Tui.Screen.text item |> Tui.Screen.link { url = "https://item.example" }
                                ]

                        else
                            Tui.Screen.text (prefix ++ item)
                }
                model.items
            )
            |> Layout.withOnLinkClick LinkSelLinkClicked
        , Layout.pane "status"
            { title = "Status", width = Layout.fill }
            (Layout.content
                [ Tui.Screen.text ("link: " ++ Maybe.withDefault "none" model.clickedUrl)
                , Tui.Screen.text ("selected: " ++ Maybe.withDefault "none" model.selectedItem)
                ]
            )
        ]


linkSelBindings : { focusedPane : Maybe String } -> LinkSelModel -> List (Layout.Group LinkSelMsg)
linkSelBindings _ _ =
    []


linkSelStatus : LinkSelModel -> { waiting : Maybe String }
linkSelStatus _ =
    { waiting = Nothing }


linkSelModal : LinkSelModel -> Maybe (Layout.Modal LinkSelMsg)
linkSelModal _ =
    Nothing


linkSelAppConfig =
    Layout.compileApp
        { data = BackendTask.succeed ()
        , init = linkSelInit
        , update = linkSelUpdate
        , view = linkSelView
        , bindings = linkSelBindings
        , status = linkSelStatus
        , modal = linkSelModal
        , onRawEvent = Nothing
        }


linkSelectableAppTest : TuiTest.TuiTest (Layout.FrameworkModel LinkSelModel LinkSelMsg) (Layout.FrameworkMsg LinkSelMsg)
linkSelectableAppTest =
    TuiTest.startApp () linkSelAppConfig



-- Scroll callback test app


type alias ScrollModel =
    { scrollPos : Int
    }


type ScrollMsg
    = Scrolled Int


scrollInit : () -> ( ScrollModel, Effect ScrollMsg )
scrollInit () =
    ( { scrollPos = 0 }, Effect.none )


scrollUpdate : Layout.UpdateContext -> ScrollMsg -> ScrollModel -> ( ScrollModel, Effect ScrollMsg )
scrollUpdate _ msg model =
    case msg of
        Scrolled pos ->
            ( { model | scrollPos = pos }, Effect.none )


scrollView : Tui.Context -> ScrollModel -> Layout.Layout ScrollMsg
scrollView _ model =
    Layout.horizontal
        [ Layout.pane "docs"
            { title = "Docs", width = Layout.fill }
            (Layout.content
                (List.range 1 50
                    |> List.map (\i -> Tui.Screen.text ("Line " ++ String.fromInt i))
                )
            )
            |> Layout.withOnScroll Scrolled
        , Layout.pane "status"
            { title = "Status", width = Layout.fill }
            (Layout.content
                [ Tui.Screen.text ("scroll: " ++ String.fromInt model.scrollPos)
                ]
            )
        ]


scrollBindings : { focusedPane : Maybe String } -> ScrollModel -> List (Layout.Group ScrollMsg)
scrollBindings _ _ =
    []


scrollStatus : ScrollModel -> { waiting : Maybe String }
scrollStatus _ =
    { waiting = Nothing }


scrollModal : ScrollModel -> Maybe (Layout.Modal ScrollMsg)
scrollModal _ =
    Nothing


scrollAppConfig =
    Layout.compileApp
        { data = BackendTask.succeed ()
        , init = scrollInit
        , update = scrollUpdate
        , view = scrollView
        , bindings = scrollBindings
        , status = scrollStatus
        , modal = scrollModal
        , onRawEvent = Nothing
        }


scrollAppTest : TuiTest.TuiTest (Layout.FrameworkModel ScrollModel ScrollMsg) (Layout.FrameworkMsg ScrollMsg)
scrollAppTest =
    TuiTest.startApp () scrollAppConfig



-- SetSelectedIndex auto-scroll test app


type alias SetSelModel =
    { selected : String
    }


type SetSelMsg
    = SetSelSelect String
    | JumpToLast
    | JumpToMiddle


setSelItems : List String
setSelItems =
    [ "item-A", "item-B", "item-C", "item-D", "item-E", "item-F", "item-G", "item-H" ]


setSelInit : () -> ( SetSelModel, Effect SetSelMsg )
setSelInit () =
    ( { selected = "" }, Effect.none )


setSelUpdate : Layout.UpdateContext -> SetSelMsg -> SetSelModel -> ( SetSelModel, Effect SetSelMsg )
setSelUpdate _ msg model =
    case msg of
        SetSelSelect item ->
            ( { model | selected = item }, Effect.none )

        JumpToLast ->
            -- Jump to last item (index 7 = "item-H")
            ( model, Effect.setSelectedIndex "items" 7 )

        JumpToMiddle ->
            -- Jump to index 5 = "item-F"
            ( model, Effect.setSelectedIndex "items" 5 )


setSelView : Tui.Context -> SetSelModel -> Layout.Layout SetSelMsg
setSelView _ model =
    Layout.horizontal
        [ Layout.pane "items"
            { title = "Items", width = Layout.fill }
            (Layout.selectableList
                { onSelect = SetSelSelect
                , view =
                    \{ selection } item ->
                        case selection of
                            Layout.Selected _ ->
                                Tui.Screen.text ("▸ " ++ item)

                            Layout.NotSelected ->
                                Tui.Screen.text ("  " ++ item)
                }
                setSelItems
            )
        ]


setSelBindings : { focusedPane : Maybe String } -> SetSelModel -> List (Layout.Group SetSelMsg)
setSelBindings _ _ =
    [ Layout.group ""
        [ Layout.charBinding 'd' "Jump to last" JumpToLast
        , Layout.charBinding 'e' "Jump to middle" JumpToMiddle
        ]
    ]


setSelStatus : SetSelModel -> { waiting : Maybe String }
setSelStatus _ =
    { waiting = Nothing }


setSelModal : SetSelModel -> Maybe (Layout.Modal SetSelMsg)
setSelModal _ =
    Nothing


setSelAppConfig =
    Layout.compileApp
        { data = BackendTask.succeed ()
        , init = setSelInit
        , update = setSelUpdate
        , view = setSelView
        , bindings = setSelBindings
        , status = setSelStatus
        , modal = setSelModal
        , onRawEvent = Nothing
        }


setSelAppTest : TuiTest.TuiTest (Layout.FrameworkModel SetSelModel SetSelMsg) (Layout.FrameworkMsg SetSelMsg)
setSelAppTest =
    TuiTest.startAppWithContext { width = 40, height = 8, colorProfile = Tui.TrueColor } () setSelAppConfig
