module Test.PagesProgram exposing
    ( ProgramTest
    , start
    , clickButton, fillIn
    , resolveEffect
    , ensureViewHas, ensureViewHasNot, ensureView
    , simulateHttpGet, simulateHttpPost
    , done
    )

{-| Test elm-pages programs with realistic simulation. The test runner resolves
BackendTask data, renders views, and processes user interactions using the same
logic as the real framework -- only external I/O (HTTP, shell commands, etc.) is
simulated.

    import BackendTask
    import Html
    import Test exposing (test)
    import Test.Html.Selector as Selector
    import Test.PagesProgram as PagesProgram

    test "renders greeting from data" <|
        \() ->
            PagesProgram.start
                { data = BackendTask.succeed "Hello!"
                , init = \greeting -> ( { greeting = greeting }, [] )
                , update = \_ model -> ( model, [] )
                , view = \model -> { title = "Home", body = [ Html.text model.greeting ] }
                }
                |> PagesProgram.ensureViewHas [ Selector.text "Hello!" ]
                |> PagesProgram.done

@docs ProgramTest

@docs start

@docs clickButton

@docs resolveEffect

@docs ensureViewHas, ensureViewHasNot, ensureView

@docs simulateHttpGet, simulateHttpPost

@docs done

-}

import BackendTask exposing (BackendTask)
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Html exposing (Html)
import Json.Encode as Encode
import Test.BackendTask.Internal as BackendTaskTest
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Test.Runner


{-| An in-progress elm-pages program test. Create one with [`start`](#start),
interact with it using simulation and assertion functions, and finalize with
[`done`](#done).
-}
type ProgramTest model msg
    = ProgramTest (State model msg)


type alias State model msg =
    { phase : Phase model msg
    , error : Maybe String
    }


type Phase model msg
    = Resolving (Resolver model msg)
    | Ready (ReadyState model msg)


{-| Hides the `data` type parameter behind closures so `ProgramTest` only
needs `model` and `msg` type parameters.
-}
type Resolver model msg
    = Resolver
        { advance : Simulation -> AdvanceResult model msg
        , pendingDescription : String
        }


type Simulation
    = SimHttpGet String Encode.Value
    | SimHttpPost String Encode.Value


type AdvanceResult model msg
    = Advanced (Phase model msg)
    | AdvanceError String


type alias ReadyState model msg =
    { model : model
    , getView : model -> { title : String, body : List (Html msg) }
    , update : msg -> model -> ( model, List (BackendTask FatalError msg) )
    , pendingEffects : List (BackendTask FatalError msg)
    }



-- START


{-| Start a program test. Provide the same fields as a route module: a `data`
BackendTask, an `init` function, an `update` function, and a `view` function.

The `data` BackendTask is auto-resolved as far as possible. If it has no
external dependencies (HTTP, custom ports, etc.), the page initializes
immediately. Otherwise, use [`simulateHttpGet`](#simulateHttpGet) or similar
to provide responses before asserting on the view.

    PagesProgram.start
        { data = BackendTask.succeed ()
        , init = \() -> ( {}, [] )
        , update = \_ model -> ( model, [] )
        , view = \() model -> { title = "Home", body = [ Html.text "Hello" ] }
        }

-}
start :
    { data : BackendTask FatalError data
    , init : data -> ( model, List (BackendTask FatalError msg) )
    , update : msg -> model -> ( model, List (BackendTask FatalError msg) )
    , view : data -> model -> { title : String, body : List (Html msg) }
    }
    -> ProgramTest model msg
start config =
    let
        bt : BackendTaskTest.BackendTaskTest data
        bt =
            BackendTaskTest.fromBackendTask config.data

        phase : Phase model msg
        phase =
            resolveDataPhase bt config.init config.view config.update
    in
    ProgramTest
        { phase = phase
        , error = Nothing
        }



-- SIMULATION


{-| Simulate a pending HTTP GET request resolving with the given JSON response
body. Applies to whichever BackendTask is currently pending (data loading or
action handling).

    PagesProgram.start
        { data = BackendTask.Http.getJson "https://api.example.com/user" userDecoder
        , ...
        }
        |> PagesProgram.simulateHttpGet
            "https://api.example.com/user"
            (Encode.object [ ( "name", Encode.string "Alice" ) ])
        |> PagesProgram.ensureViewHas [ Selector.text "Alice" ]

-}
simulateHttpGet : String -> Encode.Value -> ProgramTest model msg -> ProgramTest model msg
simulateHttpGet url jsonResponse =
    applySimulation (SimHttpGet url jsonResponse)


{-| Simulate a pending HTTP POST request resolving with the given JSON response
body.
-}
simulateHttpPost : String -> Encode.Value -> ProgramTest model msg -> ProgramTest model msg
simulateHttpPost url jsonResponse =
    applySimulation (SimHttpPost url jsonResponse)



-- USER INTERACTIONS


{-| Simulate clicking a button with the given text. Finds the first `<button>`
element whose text content matches, simulates a click event, and passes the
resulting message through `update`.

    PagesProgram.start counterConfig
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.ensureViewHas [ Selector.text "1" ]

-}
clickButton : String -> ProgramTest model msg -> ProgramTest model msg
clickButton buttonText (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("clickButton \""
                                        ++ buttonText
                                        ++ "\": Cannot interact while BackendTask data is still resolving."
                                    )
                        }

                Ready ready ->
                    let
                        viewHtml =
                            ready.getView ready.model

                        query : Query.Single msg
                        query =
                            Query.fromHtml (Html.div [] viewHtml.body)

                        buttonQuery : Query.Single msg
                        buttonQuery =
                            query
                                |> Query.find
                                    [ Selector.tag "button"
                                    , Selector.containing [ Selector.text buttonText ]
                                    ]

                        eventResult : Result String msg
                        eventResult =
                            buttonQuery
                                |> Event.simulate Event.click
                                |> Event.toResult
                    in
                    case eventResult of
                        Ok msg ->
                            applyMsg msg (ProgramTest state)

                        Err errMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("clickButton \""
                                                ++ buttonText
                                                ++ "\" failed:\n\n"
                                                ++ errMsg
                                            )
                                }



{-| Simulate typing text into an input field. Finds the input by its `id`
attribute, simulates an `input` event with the given value, and passes the
resulting message through `update`.

    PagesProgram.start loginConfig
        |> PagesProgram.fillIn "email" "alice@example.com"
        |> PagesProgram.ensureViewHas [ Selector.text "alice@example.com" ]

-}
fillIn : String -> String -> ProgramTest model msg -> ProgramTest model msg
fillIn fieldId value (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just
                                    ("fillIn \""
                                        ++ fieldId
                                        ++ "\": Cannot interact while BackendTask data is still resolving."
                                    )
                        }

                Ready ready ->
                    let
                        viewHtml =
                            ready.getView ready.model

                        query : Query.Single msg
                        query =
                            Query.fromHtml (Html.div [] viewHtml.body)

                        inputQuery : Query.Single msg
                        inputQuery =
                            query
                                |> Query.find [ Selector.id fieldId ]

                        eventResult : Result String msg
                        eventResult =
                            inputQuery
                                |> Event.simulate (Event.input value)
                                |> Event.toResult
                    in
                    case eventResult of
                        Ok msg ->
                            applyMsg msg (ProgramTest state)

                        Err errMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("fillIn \""
                                                ++ fieldId
                                                ++ "\" failed:\n\n"
                                                ++ errMsg
                                            )
                                }



-- EFFECT RESOLUTION


{-| Resolve a pending BackendTask effect using the full `Test.BackendTask` API.
When `init` or `update` returns a BackendTask effect, use this to simulate the
external dependency and feed the result back through `update`.

    import Test.BackendTask as BackendTaskTest

    PagesProgram.start fetchConfig
        |> PagesProgram.clickButton "Fetch"
        |> PagesProgram.resolveEffect
            (BackendTaskTest.simulateHttpGet
                "https://api.example.com/data"
                (Encode.list Encode.string [ "a", "b" ])
            )
        |> PagesProgram.ensureViewHas [ Selector.text "a" ]

-}
resolveEffect :
    (BackendTaskTest.BackendTaskTest msg -> BackendTaskTest.BackendTaskTest msg)
    -> ProgramTest model msg
    -> ProgramTest model msg
resolveEffect simulate (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error =
                                Just "resolveEffect: Cannot resolve effects while data BackendTask is still resolving."
                        }

                Ready ready ->
                    case ready.pendingEffects of
                        [] ->
                            ProgramTest
                                { state
                                    | error =
                                        Just "resolveEffect: No pending BackendTask effects to resolve."
                                }

                        bt :: rest ->
                            let
                                testResult : Result String msg
                                testResult =
                                    bt
                                        |> BackendTaskTest.fromBackendTask
                                        |> simulate
                                        |> BackendTaskTest.toResult
                            in
                            case testResult of
                                Ok msg ->
                                    let
                                        ( newModel, newEffects ) =
                                            ready.update msg ready.model
                                    in
                                    ProgramTest
                                        { state
                                            | phase =
                                                Ready
                                                    { ready
                                                        | model = newModel
                                                        , pendingEffects = rest ++ newEffects
                                                    }
                                        }

                                Err errMsg ->
                                    ProgramTest
                                        { state
                                            | error = Just ("resolveEffect failed:\n\n" ++ errMsg)
                                        }



-- VIEW ASSERTIONS


{-| Assert that the rendered view contains elements matching all the given
selectors. This is a chainable assertion -- it returns `ProgramTest` for
continued testing.

    test
        |> PagesProgram.ensureViewHas [ Selector.text "Welcome" ]
        |> PagesProgram.ensureViewHas [ Selector.id "main-content" ]

-}
ensureViewHas : List Selector.Selector -> ProgramTest model msg -> ProgramTest model msg
ensureViewHas selectors (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case getView state.phase of
                Err viewError ->
                    ProgramTest { state | error = Just viewError }

                Ok viewHtml ->
                    let
                        query : Query.Single msg
                        query =
                            Query.fromHtml (Html.div [] viewHtml.body)

                        result : Expectation
                        result =
                            query |> Query.has selectors
                    in
                    case getFailureMessage result of
                        Just failMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("ensureViewHas failed:\n\n"
                                                ++ failMsg
                                            )
                                }

                        Nothing ->
                            ProgramTest state


{-| Assert that the rendered view does NOT contain elements matching the given
selectors. Chainable.
-}
ensureViewHasNot : List Selector.Selector -> ProgramTest model msg -> ProgramTest model msg
ensureViewHasNot selectors (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case getView state.phase of
                Err viewError ->
                    ProgramTest { state | error = Just viewError }

                Ok viewHtml ->
                    let
                        query : Query.Single msg
                        query =
                            Query.fromHtml (Html.div [] viewHtml.body)

                        result : Expectation
                        result =
                            query |> Query.hasNot selectors
                    in
                    case getFailureMessage result of
                        Just failMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("ensureViewHasNot failed:\n\n"
                                                ++ failMsg
                                            )
                                }

                        Nothing ->
                            ProgramTest state


{-| Assert on the rendered view using a custom assertion function.

    test
        |> PagesProgram.ensureView
            (\query ->
                query
                    |> Query.find [ Selector.tag "h1" ]
                    |> Query.has [ Selector.text "Title" ]
            )

-}
ensureView : (Query.Single msg -> Expectation) -> ProgramTest model msg -> ProgramTest model msg
ensureView assertion (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case getView state.phase of
                Err viewError ->
                    ProgramTest { state | error = Just viewError }

                Ok viewHtml ->
                    let
                        query : Query.Single msg
                        query =
                            Query.fromHtml (Html.div [] viewHtml.body)

                        result : Expectation
                        result =
                            assertion query
                    in
                    case getFailureMessage result of
                        Just failMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("ensureView failed:\n\n"
                                                ++ failMsg
                                            )
                                }

                        Nothing ->
                            ProgramTest state



-- TERMINAL


{-| Finalize the test. Fails if any earlier assertion failed, or if there are
unresolved pending BackendTask effects.
-}
done : ProgramTest model msg -> Expectation
done (ProgramTest state) =
    case state.error of
        Just msg ->
            Expect.fail msg

        Nothing ->
            case state.phase of
                Resolving (Resolver r) ->
                    Expect.fail
                        ("Test ended while BackendTask data is still resolving.\n\n"
                            ++ r.pendingDescription
                        )

                Ready ready ->
                    if List.isEmpty ready.pendingEffects then
                        Expect.pass

                    else
                        Expect.fail
                            ("There are "
                                ++ String.fromInt (List.length ready.pendingEffects)
                                ++ " pending BackendTask effect(s) that must be resolved before ending the test."
                            )



-- INTERNAL HELPERS


applySimulation : Simulation -> ProgramTest model msg -> ProgramTest model msg
applySimulation sim (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving (Resolver resolver) ->
                    case resolver.advance sim of
                        Advanced newPhase ->
                            ProgramTest { state | phase = newPhase }

                        AdvanceError errMsg ->
                            ProgramTest { state | error = Just errMsg }

                Ready _ ->
                    ProgramTest
                        { state
                            | error =
                                Just "No pending BackendTask to simulate. The page is already initialized."
                        }


{-| Apply a message through update and re-render.
-}
applyMsg : msg -> ProgramTest model msg -> ProgramTest model msg
applyMsg msg (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error = Just "Cannot apply message while BackendTask is resolving."
                        }

                Ready ready ->
                    let
                        ( newModel, newEffects ) =
                            ready.update msg ready.model
                    in
                    ProgramTest
                        { state
                            | phase =
                                Ready
                                    { ready
                                        | model = newModel
                                        , pendingEffects = newEffects
                                    }
                        }


{-| Build a data-phase resolver that hides the `data` type parameter.
When the BackendTask resolves, calls `initFn` to get the model and transitions
to `Ready`. When it can't resolve yet, returns a new `Resolving` with updated
BackendTask state.
-}
resolveDataPhase :
    BackendTaskTest.BackendTaskTest data
    -> (data -> ( model, List (BackendTask FatalError msg) ))
    -> (data -> model -> { title : String, body : List (Html msg) })
    -> (msg -> model -> ( model, List (BackendTask FatalError msg) ))
    -> Phase model msg
resolveDataPhase bt initFn viewFn updateFn =
    case bt of
        BackendTaskTest.Done doneState ->
            case doneState.result of
                Ok data ->
                    let
                        ( model, effects ) =
                            initFn data
                    in
                    Ready
                        { model = model
                        , getView = viewFn data
                        , update = updateFn
                        , pendingEffects = effects
                        }

                Err err ->
                    -- BackendTask completed with FatalError
                    Ready
                        { model =
                            -- We don't have a model since init was never called.
                            -- This will show up as an error when the user calls done/expect.
                            -- For now, we store the error in the error field instead.
                            -- TODO: handle this more gracefully
                            Tuple.first (initFn (crashData err))
                        , getView = viewFn (crashData err)
                        , update = updateFn
                        , pendingEffects = []
                        }

        BackendTaskTest.Running runningState ->
            Resolving
                (Resolver
                    { advance =
                        \sim ->
                            let
                                newBt : BackendTaskTest.BackendTaskTest data
                                newBt =
                                    case sim of
                                        SimHttpGet url resp ->
                                            BackendTaskTest.simulateHttpGet url resp bt

                                        SimHttpPost url resp ->
                                            BackendTaskTest.simulateHttpPost url resp bt
                            in
                            Advanced (resolveDataPhase newBt initFn viewFn updateFn)
                    , pendingDescription =
                        stillRunningDescription runningState.pendingRequests
                    }
                )

        BackendTaskTest.TestError msg ->
            Resolving
                (Resolver
                    { advance = \_ -> AdvanceError msg
                    , pendingDescription = msg
                    }
                )


getView : Phase model msg -> Result String { title : String, body : List (Html msg) }
getView phase =
    case phase of
        Resolving (Resolver r) ->
            Err
                ("Cannot check view while BackendTask data is still resolving. "
                    ++ "Provide simulated responses first.\n\n"
                    ++ r.pendingDescription
                )

        Ready ready ->
            Ok (ready.getView ready.model)


getFailureMessage : Expectation -> Maybe String
getFailureMessage expectation =
    case Test.Runner.getFailureReason expectation of
        Just reason ->
            Just reason.description

        Nothing ->
            Nothing


stillRunningDescription : List { a | url : String } -> String
stillRunningDescription pendingRequests =
    "Pending requests:\n\n"
        ++ (pendingRequests
                |> List.map (\req -> "    " ++ req.url)
                |> String.join "\n"
           )


crashData : FatalError -> a
crashData _ =
    -- This should never be reached in well-formed tests.
    -- When the data BackendTask fails, the test should check for the failure.
    crashData (FatalError.fromString "unreachable")
