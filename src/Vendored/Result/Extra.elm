module Vendored.Result.Extra exposing (combine, combineMap, isOk, merge)


isOk : Result x a -> Bool
isOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False


merge : Result a a -> a
merge r =
    case r of
        Ok rr ->
            rr

        Err rr ->
            rr



-- https://github.com/elmcraft/core-extra/blob/2.0.0/src/Result/Extra.elm


{-| Combine a list of results into a single result (holding a list).
Also known as `sequence` on lists.
-}
combine : List (Result x a) -> Result x (List a)
combine list =
    combineHelp list []


combineHelp : List (Result x a) -> List a -> Result x (List a)
combineHelp list acc =
    case list of
        head :: tail ->
            case head of
                Ok a ->
                    combineHelp tail (a :: acc)

                Err x ->
                    Err x

        [] ->
            Ok (List.reverse acc)


{-| Map a function producing results on a list
and combine those into a single result (holding a list).
Also known as `traverse` on lists.

    combineMap f xs == combine (List.map f xs)

-}
combineMap : (a -> Result x b) -> List a -> Result x (List b)
combineMap f ls =
    combineMapHelp f ls []


combineMapHelp : (a -> Result x b) -> List a -> List b -> Result x (List b)
combineMapHelp f list acc =
    case list of
        head :: tail ->
            case f head of
                Ok a ->
                    combineMapHelp f tail (a :: acc)

                Err x ->
                    Err x

        [] ->
            Ok (List.reverse acc)
