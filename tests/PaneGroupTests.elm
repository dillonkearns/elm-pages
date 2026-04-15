module PaneGroupTests exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Tui.Layout as Layout
import Tui.Screen


suite : Test
suite =
    describe "Pane group with stable ID"
        [ test "navigateDown uses the stable group ID" <|
            \() ->
                let
                    layout : Layout.Layout Int
                    layout =
                        Layout.horizontal
                            [ Layout.paneGroup "left"
                                { tabs =
                                    [ { id = "files"
                                      , label = "Files"
                                      , content =
                                            Layout.selectableList
                                                { onSelect = identity
                                                , selected = \item -> Tui.Screen.text ("▸ " ++ item)
                                                , default = \item -> Tui.Screen.text ("  " ++ item)
                                                }
                                                [ "a.elm", "b.elm", "c.elm" ]
                                      }
                                    , { id = "worktrees"
                                      , label = "Worktrees"
                                      , content = Layout.content [ Tui.Screen.text "wt" ]
                                      }
                                    ]
                                , activeTab = "files"
                                , width = Layout.fill
                                }
                            ]

                    state : Layout.State
                    state =
                        Layout.init |> Layout.withContext { width = 30, height = 8 }

                    -- Navigate using the GROUP id, not the tab id
                    ( newState, maybeMsg ) =
                        Layout.navigateDown "left" layout state
                in
                Expect.all
                    [ \_ -> Layout.selectedIndex "left" newState |> Expect.equal 1
                    , \_ -> maybeMsg |> Expect.equal (Just 1)
                    ]
                    ()
        , test "selectedIndex uses stable group ID" <|
            \() ->
                let
                    layout : Layout.Layout Int
                    layout =
                        Layout.horizontal
                            [ Layout.paneGroup "left"
                                { tabs =
                                    [ { id = "files"
                                      , label = "Files"
                                      , content =
                                            Layout.selectableList
                                                { onSelect = identity
                                                , selected = \item -> Tui.Screen.text ("▸ " ++ item)
                                                , default = \item -> Tui.Screen.text ("  " ++ item)
                                                }
                                                [ "a.elm", "b.elm" ]
                                      }
                                    ]
                                , activeTab = "files"
                                , width = Layout.fill
                                }
                            ]

                    state : Layout.State
                    state =
                        Layout.init |> Layout.withContext { width = 30, height = 8 }

                    ( newState, _ ) =
                        Layout.navigateDown "left" layout state
                in
                Layout.selectedIndex "left" newState |> Expect.equal 1
        , test "state preserved when switching tabs" <|
            \() ->
                let
                    makeLayout : String -> Layout.Layout Int
                    makeLayout activeTab =
                        Layout.horizontal
                            [ Layout.paneGroup "left"
                                { tabs =
                                    [ { id = "files"
                                      , label = "Files"
                                      , content =
                                            Layout.selectableList
                                                { onSelect = identity
                                                , selected = \item -> Tui.Screen.text ("▸ " ++ item)
                                                , default = \item -> Tui.Screen.text ("  " ++ item)
                                                }
                                                [ "a.elm", "b.elm", "c.elm" ]
                                      }
                                    , { id = "worktrees"
                                      , label = "Worktrees"
                                      , content =
                                            Layout.selectableList
                                                { onSelect = identity
                                                , selected = \item -> Tui.Screen.text ("▸ " ++ item)
                                                , default = \item -> Tui.Screen.text ("  " ++ item)
                                                }
                                                [ "wt1", "wt2" ]
                                      }
                                    ]
                                , activeTab = activeTab
                                , width = Layout.fill
                                }
                            ]

                    state : Layout.State
                    state =
                        Layout.init |> Layout.withContext { width = 30, height = 8 }

                    -- Navigate down twice in files tab
                    ( stateAfterFiles, _ ) =
                        Layout.navigateDown "left" (makeLayout "files") state
                            |> (\( s, _ ) -> Layout.navigateDown "left" (makeLayout "files") s)

                    -- Switch to worktrees tab, navigate down once
                    ( stateAfterWorktrees, _ ) =
                        Layout.navigateDown "left" (makeLayout "worktrees") stateAfterFiles

                    -- Switch back to files — selection should still be at 2
                in
                Expect.all
                    [ \_ ->
                        -- After switching back to files, files selection preserved
                        Layout.switchTab "left" "files" stateAfterWorktrees
                            |> Layout.selectedIndex "left"
                            |> Expect.equal 2
                    , \_ ->
                        -- worktrees selection is at 1
                        Layout.selectedIndex "left" stateAfterWorktrees
                            |> Expect.equal 1
                    ]
                    ()
        , test "switchTab changes which tab is active" <|
            \() ->
                let
                    state : Layout.State
                    state =
                        Layout.init
                            |> Layout.withContext { width = 30, height = 5 }
                            |> Layout.switchTab "left" "files"
                in
                Expect.all
                    [ \_ ->
                        Layout.activeTab "left" state
                            |> Expect.equal (Just "files")
                    , \_ ->
                        Layout.switchTab "left" "worktrees" state
                            |> Layout.activeTab "left"
                            |> Expect.equal (Just "worktrees")
                    ]
                    ()
        , test "content changes when tab switches" <|
            \() ->
                let
                    makeLayout : String -> Layout.Layout Int
                    makeLayout tab =
                        Layout.horizontal
                            [ Layout.paneGroup "left"
                                { tabs =
                                    [ { id = "files", label = "Files", content = Layout.content [ Tui.Screen.text "files-content" ] }
                                    , { id = "worktrees", label = "Worktrees", content = Layout.content [ Tui.Screen.text "worktrees-content" ] }
                                    ]
                                , activeTab = tab
                                , width = Layout.fill
                                }
                            ]

                    state : Layout.State
                    state =
                        Layout.init |> Layout.withContext { width = 40, height = 5 }

                    rendered : String
                    rendered =
                        makeLayout "worktrees"
                            |> Layout.toScreen state
                            |> Tui.Screen.toString
                in
                Expect.all
                    [ \s -> s |> String.contains "worktrees-content" |> Expect.equal True
                    , \s -> s |> String.contains "files-content" |> Expect.equal False
                    ]
                    rendered
        ]
