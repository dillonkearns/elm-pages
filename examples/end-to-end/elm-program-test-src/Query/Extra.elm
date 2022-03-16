module Query.Extra exposing (oneOf)

import Html
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Test.Runner


{-| This is a hack for the fact that elm-html-test does not provide a way to force a `Query.Single` into an error state.
-}
fail : String -> Query.Single msg -> Query.Single msg
fail message _ =
    Html.text ("ERROR: " ++ message)
        |> Query.fromHtml
        |> Query.find [ Selector.text "SHOULD NOT HAVE ERROR" ]


{-| Determines whether the given `Query.Single` is an error (failed to match a node)
-}
isFailed : Query.Single msg -> Bool
isFailed single =
    case single |> Query.has [] |> Test.Runner.getFailureReason of
        Just _ ->
            True

        Nothing ->
            False


{-| TODO: Is it strange that this takes a `List (Single -> Single)`? Is it safer or more sensible to take `List (List Selector)` and then implicily only work with `Query.find`?
-}
oneOf : List (Query.Single msg -> Query.Single msg) -> Query.Single msg -> Query.Single msg
oneOf options single =
    if isFailed single then
        -- the input single is an error, so just return that
        single

    else
        case options of
            [] ->
                fail "Query.Extra.oneOf was given an empty list of options" single

            [ last ] ->
                -- this is the last option, so if it fails, we want to return that failure
                -- TODO: if the all failed, give a better error message about everything that failed
                single |> last

            next :: rest1 :: rest ->
                if isFailed (next single) then
                    -- this option failed, so try the remaining ones
                    oneOf (rest1 :: rest) single

                else
                    -- this option passed, so return success
                    next single
