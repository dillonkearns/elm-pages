-- Copied from rtfeldman/node-test-runner : elm/src/Test/Reporter/Console/Format/Monochrome.elm
-- https://github.com/rtfeldman/node-test-runner/blob/master/elm/src/Test/Reporter/Console/Format/Monochrome.elm
-- Published under BSD-3-Clause license, see LICENSE_node-test-runner


module Vendored.FormatMonochrome exposing (formatEquality)

import Vendored.Highlightable as Highlightable exposing (Highlightable(..))


formatEquality : List (Highlightable String) -> List (Highlightable String) -> ( String, String )
formatEquality highlightedExpected highlightedActual =
    let
        ( formattedExpected, expectedIndicators ) =
            highlightedExpected
                |> List.map (fromHighlightable "▲")
                |> List.unzip

        ( formattedActual, actualIndicators ) =
            highlightedActual
                |> List.map (fromHighlightable "▼")
                |> List.unzip

        combinedExpected =
            String.join "\n"
                [ String.join "" formattedExpected
                , String.join "" expectedIndicators
                ]

        combinedActual =
            String.join "\n"
                [ String.join "" actualIndicators
                , String.join "" formattedActual
                ]
    in
    ( combinedExpected, combinedActual )


fromHighlightable : String -> Highlightable String -> ( String, String )
fromHighlightable indicator =
    Highlightable.resolve
        { fromHighlighted = \char -> ( char, indicator )
        , fromPlain = \char -> ( char, " " )
        }
