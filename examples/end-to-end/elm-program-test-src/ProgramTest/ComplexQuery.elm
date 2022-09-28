module ProgramTest.ComplexQuery exposing (ComplexQuery, Failure(..), FailureContext, FailureContext1(..), Highlight, MsgOrSubmit(..), Priority, check, exactlyOneOf, find, findButNot, map, run, simulate, simulateSubmit, succeed)

import Json.Encode as Json
import ProgramTest.TestHtmlHacks as TestHtmlHacks
import ProgramTest.TestHtmlParser as TestHtmlParser
import Set exposing (Set)
import Test.Html.Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector exposing (Selector)
import Test.Runner


type ComplexQuery a
    = QueryResult State Highlight (List FailureContext1) (Result Failure a)


map : (a -> b) -> ComplexQuery a -> ComplexQuery b
map function (QueryResult state highlight failures result) =
    QueryResult state highlight failures (Result.map function result)


succeed : a -> ComplexQuery a
succeed a =
    QueryResult initState Set.empty [] (Ok a)


type alias Priority =
    Int


type alias State =
    { priority : Priority
    }


initState : State
initState =
    { priority = 0
    }


type Failure
    = QueryFailed (List (Result String String))
    | SimulateFailed String
    | NoMatches String (List ( String, Priority, ( List FailureContext1, Failure ) ))
    | TooManyMatches String (List ( String, Priority, List FailureContext1 ))


type alias FailureContext =
    List FailureContext1


type FailureContext1
    = FindSucceeded (Maybe String) (() -> List String)
    | CheckSucceeded String (List FailureContext1)
    | Description (Result String String)


type alias Highlight =
    Set String


run : ComplexQuery a -> ( Highlight, Result ( List FailureContext1, Failure ) a )
run (QueryResult _ highlight context result) =
    ( highlight
    , case result of
        Ok a ->
            Ok a

        Err error ->
            Err ( List.reverse context, error )
    )


find : Maybe String -> List String -> List Selector -> ComplexQuery (Query.Single msg) -> ComplexQuery (Query.Single msg)
find description highlight selectors prev =
    case prev of
        QueryResult _ _ _ (Err _) ->
            prev

        QueryResult state prevHighlight prevContext (Ok source) ->
            case Test.Runner.getFailureReason (Query.has [ Selector.all selectors ] source) of
                Just _ ->
                    let
                        error =
                            firstErrorOf source
                                [ selectors
                                , [ Selector.all selectors ]
                                ]

                        context =
                            case description of
                                Nothing ->
                                    []

                                Just desc ->
                                    [ Description (Err desc) ]
                    in
                    QueryResult
                        { state
                            | priority = state.priority + countSuccesses error
                        }
                        (Set.union (Set.fromList highlight) prevHighlight)
                        (context ++ prevContext)
                        (Err (QueryFailed error))

                Nothing ->
                    QueryResult
                        { state
                            | priority = state.priority + List.length selectors
                        }
                        (Set.union (Set.fromList highlight) prevHighlight)
                        (FindSucceeded description (\() -> TestHtmlHacks.getPassingSelectors selectors source) :: prevContext)
                        (Ok (Query.find selectors source))


exactlyOneOf : String -> List ( String, ComplexQuery a -> ComplexQuery b ) -> ComplexQuery a -> ComplexQuery b
exactlyOneOf description options prev =
    case prev of
        QueryResult state prevHighlight prevContext (Err err) ->
            QueryResult state prevHighlight prevContext (Err err)

        QueryResult state prevHighlight prevContext (Ok _) ->
            let
                results : List ( String, ComplexQuery b )
                results =
                    List.map (Tuple.mapSecond (\option -> option prev)) options

                successes : List ( String, ComplexQuery b )
                successes =
                    List.filter (isSuccess << Tuple.second) results

                isSuccess res =
                    case res of
                        QueryResult _ _ _ (Err _) ->
                            False

                        QueryResult _ _ _ (Ok _) ->
                            True

                collectHighlight (QueryResult _ highlight _ _) =
                    highlight

                highlights =
                    List.map (collectHighlight << Tuple.second) results
                        |> List.foldl Set.union Set.empty

                collectError ( desc, QueryResult newState _ context result ) =
                    case result of
                        Ok _ ->
                            Nothing

                        Err x ->
                            Just
                                ( desc
                                , newState.priority
                                , ( List.reverse context, x )
                                )
            in
            case successes of
                [ ( _, one ) ] ->
                    one

                [] ->
                    let
                        failures =
                            List.filterMap collectError results
                    in
                    QueryResult
                        state
                        (Set.union highlights prevHighlight)
                        prevContext
                        (Err (NoMatches description failures))

                many ->
                    let
                        matches =
                            List.map
                                (\( desc, QueryResult newState _ context _ ) ->
                                    ( desc, newState.priority, context )
                                )
                                many
                    in
                    QueryResult
                        state
                        (Set.union highlights prevHighlight)
                        prevContext
                        (Err (TooManyMatches description matches))


{-|

  - `good`: the primary selector that must match
  - `bads`: a list of selectors that must NOT match
  - `onError`: the selector to use to produce an error message if any of the checks fail

-}
findButNot :
    Maybe String
    -> List String
    ->
        { good : List Selector
        , bads : List (List Selector)
        , onError : List Selector
        }
    -> ComplexQuery (Query.Single msg)
    -> ComplexQuery (Query.Single msg)
findButNot description highlight { good, bads, onError } prev =
    case prev of
        QueryResult _ _ _ (Err _) ->
            prev

        QueryResult state prevHighlight prevContext (Ok source) ->
            -- This is tricky because Test.Html doesn't provide a way to search for an attribute being *not* present.
            -- So we have to check if a selector we don't want *is* present, and manually force a failure if it is.
            let
                addDescription =
                    case description of
                        Nothing ->
                            []

                        Just desc ->
                            [ Description (Err desc) ]

                checkBads : Priority -> List (List Selector) -> Query.Single msg -> ComplexQuery (Query.Single msg)
                checkBads extraPriority bads_ found =
                    case bads_ of
                        [] ->
                            QueryResult
                                { state | priority = state.priority + extraPriority + 1 }
                                (Set.union (Set.fromList highlight) prevHighlight)
                                -- TODO: add the not bads to the context (or alternatively, add the "onErrors", but convert them all to successes)
                                (FindSucceeded description (\() -> TestHtmlHacks.getPassingSelectors good source) :: prevContext)
                                (Ok found)

                        nextBad :: rest ->
                            let
                                isBad =
                                    Query.has [ Selector.all nextBad ] source
                            in
                            case Test.Runner.getFailureReason isBad of
                                Nothing ->
                                    -- the element matches the bad selectors; produce a Query using the onError selectors that will fail that will show a reasonable failure message
                                    let
                                        error =
                                            firstErrorOf source
                                                [ good
                                                , [ Selector.all good ]
                                                , onError
                                                , [ Selector.all onError ]
                                                ]
                                    in
                                    QueryResult
                                        { state | priority = state.priority + extraPriority + countSuccesses error }
                                        (Set.union (Set.fromList highlight) prevHighlight)
                                        (addDescription ++ prevContext)
                                        (Err (QueryFailed error))

                                Just _ ->
                                    -- the element we found is not bad; continue on to the next check
                                    checkBads (extraPriority + List.length nextBad) rest found

                isGood =
                    Query.has [ Selector.all good ] source
            in
            case Test.Runner.getFailureReason isGood of
                Just _ ->
                    -- Couldn't find it, so report the best error message we can
                    let
                        error =
                            firstErrorOf source
                                [ good
                                , [ Selector.all good ]
                                ]
                    in
                    QueryResult
                        { state | priority = state.priority + countSuccesses error }
                        (Set.union (Set.fromList highlight) prevHighlight)
                        prevContext
                        (Err (QueryFailed error))

                Nothing ->
                    Query.find good source
                        |> checkBads (List.length good) bads


type MsgOrSubmit msg
    = SubmitMsg msg
    | Submit


simulateSubmit : ComplexQuery (Query.Single msg) -> ComplexQuery (MsgOrSubmit msg)
simulateSubmit prev =
    case prev of
        QueryResult state prevHighlight prevContext (Err err) ->
            QueryResult state prevHighlight prevContext (Err err)

        QueryResult state prevHighlight prevContext (Ok source) ->
            case
                source
                    |> Test.Html.Event.simulate Test.Html.Event.submit
                    |> Test.Html.Event.toResult
            of
                Err message ->
                    -- TODO include details of the form to submit, etc.? Or gather that context elsewhere?
                    QueryResult state prevHighlight prevContext (Ok Submit)

                Ok msg ->
                    QueryResult state prevHighlight prevContext (Ok (SubmitMsg msg))


simulate : ( String, Json.Value ) -> ComplexQuery (Query.Single msg) -> ComplexQuery msg
simulate event prev =
    case prev of
        QueryResult state prevHighlight prevContext (Err err) ->
            QueryResult state prevHighlight prevContext (Err err)

        QueryResult state prevHighlight prevContext (Ok source) ->
            case
                source
                    |> Test.Html.Event.simulate event
                    |> Test.Html.Event.toResult
            of
                Err message ->
                    QueryResult
                        state
                        prevHighlight
                        (Description (Err ("simulate " ++ Tuple.first event)) :: prevContext)
                        (Err (SimulateFailed (TestHtmlHacks.parseSimulateFailure message)))

                Ok msg ->
                    QueryResult state prevHighlight prevContext (Ok msg)


{-| Ensure that the given query succeeds, but then ignore its result.
-}
check : String -> (ComplexQuery a -> ComplexQuery ignored) -> ComplexQuery a -> ComplexQuery a
check description checkQuery prev =
    case prev of
        QueryResult _ _ _ (Err _) ->
            prev

        QueryResult state prevHighlight prevContext (Ok source) ->
            let
                (QueryResult checkedState highlight checkContext checkResult) =
                    checkQuery (QueryResult state prevHighlight [] (Ok source))
            in
            case checkResult of
                Err failure ->
                    QueryResult
                        checkedState
                        (Set.union highlight prevHighlight)
                        (Description (Err description) :: checkContext ++ prevContext)
                        (Err failure)

                Ok _ ->
                    QueryResult
                        { state | priority = checkedState.priority }
                        (Set.union highlight prevHighlight)
                        (CheckSucceeded description checkContext :: prevContext)
                        (Ok source)


firstErrorOf : Query.Single msg -> List (List Selector) -> List (Result String String)
firstErrorOf source choices =
    case choices of
        [] ->
            [ Err "PLEASE REPORT THIS AT <https://github.com/avh4/elm-program-test/issues>: firstErrorOf: asked to report an error but none of the choices failed" ]

        next :: rest ->
            case Test.Runner.getFailureReason (Query.has next source) of
                Just reason ->
                    case TestHtmlHacks.parseFailureReportWithoutHtml reason.description of
                        Ok (TestHtmlParser.QueryFailure _ _ (TestHtmlParser.Has _ results)) ->
                            results

                        Ok (TestHtmlParser.EventFailure name _) ->
                            [ Err ("PLEASE REPORT THIS AT <https://github.com/avh4/elm-program-test/issues>: firstErrorOf: got unexpected EventFailure \"" ++ name ++ "\"") ]

                        Err err ->
                            [ Err ("PLEASE REPORT THIS AT <https://github.com/avh4/elm-program-test/issues>: firstErrorOf: couldn't parse failure report: " ++ err) ]

                Nothing ->
                    firstErrorOf source rest


countSuccesses : List (Result String String) -> Int
countSuccesses results =
    List.length (List.filter isOk results)


isOk : Result x a -> Bool
isOk result =
    case result of
        Ok _ ->
            True

        Err _ ->
            False
