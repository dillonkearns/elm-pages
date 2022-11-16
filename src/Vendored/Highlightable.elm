-- Copied from rtfeldman/node-test-runner : elm/src/Test/Reporter/Highlightable.elm
-- https://github.com/rtfeldman/node-test-runner/blob/master/elm/src/Test/Reporter/Highlightable.elm
-- Published under BSD-3-Clause license, see LICENSE_node-test-runner


module Vendored.Highlightable exposing (Highlightable, diffLists, map, resolve)

import Vendored.Diff as Diff exposing (Change(..))


type Highlightable a
    = Highlighted a
    | Plain a


resolve : { fromHighlighted : a -> b, fromPlain : a -> b } -> Highlightable a -> b
resolve { fromHighlighted, fromPlain } highlightable =
    case highlightable of
        Highlighted val ->
            fromHighlighted val

        Plain val ->
            fromPlain val


diffLists : List a -> List a -> List (Highlightable a)
diffLists expected actual =
    -- TODO make sure this looks reasonable for multiline strings
    Diff.diff expected actual
        |> List.concatMap fromDiff


map : (a -> b) -> Highlightable a -> Highlightable b
map transform highlightable =
    case highlightable of
        Highlighted val ->
            Highlighted (transform val)

        Plain val ->
            Plain (transform val)


fromDiff : Change a -> List (Highlightable a)
fromDiff diff =
    case diff of
        Added _ ->
            []

        Removed char ->
            [ Highlighted char ]

        NoChange char ->
            [ Plain char ]
