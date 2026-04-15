module TuiStarsTests exposing (suite, tuiTests)

import Json.Encode as Encode
import Test exposing (Test)
import Test.BackendTask as BackendTaskTest
import Tui.Sub
import Tui.Test as TuiTest
import TuiStars


suite : Test
suite =
    TuiTest.toTest tuiTests


tuiTests : TuiTest.Test
tuiTests =
    TuiTest.describe "TuiStars"
        [ TuiTest.test "seeds repo from data and fetches stars"
            (TuiTest.startApp
                (BackendTaskTest.init
                    |> BackendTaskTest.withEnv "GITHUB_REPO" "elm/core"
                )
                TuiStars.app
                |> TuiTest.ensureViewHas "elm/core"
                |> TuiTest.ensureViewHas "Press Enter to fetch"
                |> TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
                |> TuiTest.ensureViewHas "Fetching..."
                |> TuiTest.resolveEffect
                    (BackendTaskTest.simulateHttpGet
                        "https://api.github.com/repos/elm/core"
                        (Encode.object [ ( "stargazers_count", Encode.int 7500 ) ])
                    )
                |> TuiTest.ensureViewHas "7500"
                |> TuiTest.ensureViewHas "stars on elm/core"
                |> TuiTest.expectRunning
            )
        , TuiTest.test "input can paste a new repo and refetch"
            (TuiTest.startApp BackendTaskTest.init TuiStars.app
                |> TuiTest.pressKeyWith
                    { key = Tui.Sub.Character 'u'
                    , modifiers = [ Tui.Sub.Ctrl ]
                    }
                |> TuiTest.paste "elm/compiler"
                |> TuiTest.ensureViewHas "elm/compiler"
                |> TuiTest.pressKeyWith { key = Tui.Sub.Enter, modifiers = [] }
                |> TuiTest.resolveEffect
                    (BackendTaskTest.simulateHttpGet
                        "https://api.github.com/repos/elm/compiler"
                        (Encode.object [ ( "stargazers_count", Encode.int 7800 ) ])
                    )
                |> TuiTest.ensureViewHas "7800"
                |> TuiTest.ensureViewHas "stars on elm/compiler"
                |> TuiTest.expectRunning
            )
        ]
