module TuiStarsTests exposing (suite, tuiTests)

import Json.Encode as Encode
import Test exposing (Test)
import Test.BackendTask as BackendTaskTest
import Test.Tui as TuiTest
import Tui.Sub
import TuiStars


suite : Test
suite =
    TuiTest.toTest tuiTests


tuiTests : TuiTest.Test
tuiTests =
    let
        setup : BackendTaskTest.TestSetup
        setup =
            BackendTaskTest.init
                |> BackendTaskTest.withFile "elm.json" """{ "type": "application" }"""
    in
    TuiTest.describe "TuiStars"
        [ TuiTest.test "seeds the default repo from data and fetches stars"
            (TuiTest.start setup TuiStars.app)
            [ TuiTest.ensureViewHas "dillonkearns/elm-pages"
            , TuiTest.ensureViewHas "Press Enter to fetch"
            , TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
            , TuiTest.ensureViewHas "Fetching..."
            , TuiTest.resolveEffectWith
                (BackendTaskTest.simulateHttpGet
                    "https://api.github.com/repos/dillonkearns/elm-pages"
                    (Encode.object [ ( "stargazers_count", Encode.int 7500 ) ])
                )
            , TuiTest.ensureViewHas "7500"
            , TuiTest.ensureViewHas "stars on dillonkearns/elm-pages"
            , TuiTest.expectRunning
            ]
        , TuiTest.test "input can paste a new repo and refetch"
            (TuiTest.start setup TuiStars.app)
            [ TuiTest.pressKeyWith
                { key = Tui.Sub.Character 'u'
                , modifiers = [ Tui.Sub.Ctrl ]
                }
            , TuiTest.paste "elm/compiler"
            , TuiTest.ensureViewHas "elm/compiler"
            , TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
            , TuiTest.resolveEffectWith
                (BackendTaskTest.simulateHttpGet
                    "https://api.github.com/repos/elm/compiler"
                    (Encode.object [ ( "stargazers_count", Encode.int 7800 ) ])
                )
            , TuiTest.ensureViewHas "7800"
            , TuiTest.ensureViewHas "stars on elm/compiler"
            , TuiTest.expectRunning
            ]
        ]
