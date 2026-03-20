module Test.PagesProgram exposing
    ( ProgramTest
    , start, startPlatform
    , clickButton, clickLink, fillIn, check
    , navigateTo, ensureBrowserUrl
    , resolveEffect
    , ensureViewHas, ensureViewHasNot, ensureView
    , simulateHttpGet, simulateHttpPost
    , done
    , Snapshot, toSnapshots, withModelToString
    )

{-| Test elm-pages programs with realistic simulation.

For full-fidelity route tests, use [`startPlatform`](#startPlatform) with a
generated `TestApp` module. This drives the real elm-pages framework
(`Pages.Internal.Platform`) so that shared data, shared view, navigation,
form submission, and all other framework behavior works identically to
production. Only external I/O (HTTP, shell commands, etc.) is simulated
via a mock resolver.

    import TestApp
    import Test exposing (test)
    import Test.Html.Selector as Selector
    import Test.PagesProgram as PagesProgram

    test "renders index page" <|
        \() ->
            TestApp.start "/" mockData
                |> PagesProgram.ensureViewHas [ Selector.text "Hello!" ]
                |> PagesProgram.done

For simple, self-contained page-state tests that don't need the full framework,
use [`start`](#start) with inline config.

@docs ProgramTest

@docs start, startPlatform

@docs clickButton, clickLink, fillIn, check

@docs resolveEffect

@docs ensureViewHas, ensureViewHasNot, ensureView

@docs simulateHttpGet, simulateHttpPost

@docs done


## Snapshots

Snapshots record the rendered view at each step of the test pipeline. Use them
with the visual test runner to step through your test in the browser.

@docs Snapshot, toSnapshots, withModelToString

-}

import BackendTask exposing (BackendTask)
import Browser
import Bytes
import Bytes.Decode
import Bytes.Encode
import Dict
import Expect exposing (Expectation)
import FatalError exposing (FatalError)
import Html exposing (Html)
import Internal.Request
import Pages.Internal.FatalError
import Json.Encode as Encode
import PageServerResponse exposing (PageServerResponse(..))
import Pages.Internal.Platform as Platform
import Pages.Internal.ResponseSketch as ResponseSketch
import Pages.StaticHttp.Request
import Pages.StaticHttpRequest
import RequestsAndPending
import Test.BackendTask.Internal as BackendTaskTest
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Test.Runner
import Time
import Url exposing (Url)
import UrlPath


{-| An in-progress elm-pages program test. Create one with [`start`](#start),
interact with it using simulation and assertion functions, and finalize with
[`done`](#done).
-}
type ProgramTest model msg
    = ProgramTest (State model msg)


type alias State model msg =
    { phase : Phase model msg
    , error : Maybe String
    , snapshots : List Snapshot
    , modelToString : Maybe (model -> String)
    }


{-| A snapshot of the program state at a point in the test pipeline. Used by
the visual test runner to step through test execution in the browser.

`body` contains the rendered HTML at this step. `title` is the page title.
`rerender` lets the viewer re-render the view (e.g., at a different size).
`modelState` contains the model as a string if `withModelToString` was used.

-}
type alias Snapshot =
    { label : String
    , title : String
    , body : List (Html Never)
    , rerender : () -> { title : String, body : List (Html Never) }
    , hasPendingEffects : Bool
    , modelState : Maybe String
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
    , onNavigate : Maybe (String -> msg)
    , getBrowserUrl : Maybe (model -> String)
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

        initSnapshot : List Snapshot
        initSnapshot =
            case phase of
                Ready ready ->
                    let
                        viewResult =
                            ready.getView ready.model
                    in
                    [ { label = "start"
                      , title = viewResult.title
                      , body = (mapViewToSnapshot viewResult).body
                      , rerender = \() -> mapViewToSnapshot (ready.getView ready.model)
                      , hasPendingEffects = not (List.isEmpty ready.pendingEffects)
                      , modelState = Nothing
                      }
                    ]

                Resolving _ ->
                    [ { label = "start"
                      , title = "(resolving data...)"
                      , body = []
                      , rerender = \() -> { title = "(resolving data...)", body = [] }
                      , hasPendingEffects = True
                      , modelState = Nothing
                      }
                    ]
    in
    ProgramTest
        { phase = phase
        , error = Nothing
        , snapshots = initSnapshot
        , modelToString = Nothing
        }



{-| Start a full-fidelity elm-pages test by driving `Pages.Internal.Platform`
directly. The generated `TestApp` module provides the `config` (which is
`Main.config`), so the typical usage is:

    TestApp.start "/" mockData
        |> PagesProgram.ensureViewHas [ Selector.text "Hello" ]
        |> PagesProgram.done

Where `TestApp.start = PagesProgram.startPlatform Main.config`.

The mock resolver maps outgoing `BackendTask.Http` requests to responses.
All framework behavior (shared data, shared view, navigation, form state)
works identically to production because we drive the real Platform code.

-}
startPlatform config initialPath mockResolver =
    let
        baseUrl =
            "https://localhost:1234"

        initialUrl =
            makeTestUrl baseUrl initialPath
    in
    case resolveInitialData config initialUrl initialPath mockResolver of
        Err errMsg ->
            ProgramTest
                { phase =
                    Resolving
                        (Resolver
                            { advance = \_ -> AdvanceError errMsg
                            , pendingDescription = errMsg
                            }
                        )
                , error = Just errMsg
                , snapshots = []
                , modelToString = Nothing
                }

        Ok pageDataBytes ->
            let
                flags =
                    Encode.object []

                ( initModel, _ ) =
                    Platform.init config flags initialUrl Nothing

                ( readyModel, readyEffect ) =
                    Platform.update config (Platform.FrozenViewsReady (Just pageDataBytes)) initModel

                processEffect eff model =
                    processEffects config mockResolver baseUrl model eff 100

                finalModel =
                    processEffect readyEffect readyModel

                updateFn msg model =
                    let
                        ( newModel, effect ) =
                            Platform.update config msg model

                        processedModel =
                            processEffect effect newModel
                    in
                    ( processedModel, [] )

                viewFn model =
                    let
                        doc =
                            Platform.view config model
                    in
                    { title = doc.title, body = doc.body }

                ready =
                    { model = finalModel
                    , getView = viewFn
                    , update = updateFn
                    , pendingEffects = []
                    , onNavigate =
                        Just
                            (\href ->
                                Platform.LinkClicked
                                    (Browser.Internal (makeTestUrl baseUrl href))
                            )
                    , getBrowserUrl =
                        Just (\m -> Url.toString m.url)
                    }

                viewResult =
                    viewFn finalModel

                initSnapshot =
                    { label = "start"
                    , title = viewResult.title
                    , body = (mapViewToSnapshot viewResult).body
                    , rerender = \() -> mapViewToSnapshot (viewFn finalModel)
                    , hasPendingEffects = False
                    , modelState = Nothing
                    }
            in
            ProgramTest
                { phase = Ready ready
                , error = Nothing
                , snapshots = [ initSnapshot ]
                , modelToString = Nothing
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
                            applyMsgWithLabel ("clickButton \"" ++ buttonText ++ "\"") msg (ProgramTest state)

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
                            applyMsgWithLabel ("fillIn \"" ++ fieldId ++ "\"") msg (ProgramTest state)

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



{-| Simulate clicking a link with the given text and href. Verifies that a
matching `<a>` element exists in the view, then triggers navigation.

In framework-driven tests (`startPlatform`), this dispatches `LinkClicked`
through the real Platform, which handles URL changes, data loading, and
re-rendering just like production.

    TestApp.start "/links" mockData
        |> PagesProgram.clickLink "Counter page" "/counter"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 0" ]

-}
clickLink : String -> String -> ProgramTest model msg -> ProgramTest model msg
clickLink linkText href (ProgramTest state) =
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
                                    ("clickLink \""
                                        ++ linkText
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

                        -- Verify link exists in the view
                        linkExists : Expectation
                        linkExists =
                            query
                                |> Query.find
                                    [ Selector.tag "a"
                                    , Selector.containing [ Selector.text linkText ]
                                    ]
                                |> Query.has []
                    in
                    case getFailureMessage linkExists of
                        Just errMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("clickLink \""
                                                ++ linkText
                                                ++ "\" failed: link not found\n\n"
                                                ++ errMsg
                                            )
                                }

                        Nothing ->
                            -- Link exists. Navigate using onNavigate if available.
                            case ready.onNavigate of
                                Just navigate ->
                                    applyMsgWithLabel
                                        ("clickLink \"" ++ linkText ++ "\"")
                                        (navigate href)
                                        (ProgramTest state)

                                Nothing ->
                                    -- No navigation handler (old API). Try event simulation.
                                    let
                                        linkQuery =
                                            query
                                                |> Query.find
                                                    [ Selector.tag "a"
                                                    , Selector.containing [ Selector.text linkText ]
                                                    ]

                                        eventResult =
                                            linkQuery
                                                |> Event.simulate Event.click
                                                |> Event.toResult
                                    in
                                    case eventResult of
                                        Ok msg ->
                                            applyMsgWithLabel ("clickLink \"" ++ linkText ++ "\"") msg (ProgramTest state)

                                        Err _ ->
                                            ProgramTest state


{-| Navigate directly to a URL path. In framework-driven tests, this triggers
the full Platform navigation cycle: `LinkClicked` -> `UrlChanged` ->
data loading -> re-render.

    TestApp.start "/" mockData
        |> PagesProgram.navigateTo "/counter"
        |> PagesProgram.ensureViewHas [ Selector.text "Count: 0" ]

-}
navigateTo : String -> ProgramTest model msg -> ProgramTest model msg
navigateTo path (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state
                            | error = Just "navigateTo: Cannot navigate while BackendTask data is still resolving."
                        }

                Ready ready ->
                    case ready.onNavigate of
                        Just navigate ->
                            applyMsgWithLabel
                                ("navigateTo \"" ++ path ++ "\"")
                                (navigate path)
                                (ProgramTest state)

                        Nothing ->
                            ProgramTest
                                { state
                                    | error = Just "navigateTo: Navigation is only supported with startPlatform (framework-driven tests)."
                                }


{-| Assert on the current browser URL. Use with framework-driven tests
(`startPlatform`) where navigation is tracked by the Platform.

    TestApp.start "/hello" mockData
        |> PagesProgram.ensureBrowserUrl
            (\url -> url |> Expect.equal "https://localhost:1234/hello")

-}
ensureBrowserUrl : (String -> Expectation) -> ProgramTest model msg -> ProgramTest model msg
ensureBrowserUrl assertion (ProgramTest state) =
    case state.error of
        Just _ ->
            ProgramTest state

        Nothing ->
            case state.phase of
                Resolving _ ->
                    ProgramTest
                        { state | error = Just "ensureBrowserUrl: Cannot check URL while data is resolving." }

                Ready ready ->
                    case ready.getBrowserUrl of
                        Just getUrl ->
                            let
                                currentUrl =
                                    getUrl ready.model

                                result =
                                    assertion currentUrl
                            in
                            case getFailureMessage result of
                                Just failMsg ->
                                    ProgramTest
                                        { state
                                            | error =
                                                Just ("ensureBrowserUrl failed:\n\n" ++ failMsg)
                                        }

                                Nothing ->
                                    ProgramTest state

                        Nothing ->
                            ProgramTest
                                { state
                                    | error = Just "ensureBrowserUrl: URL tracking is only supported with startPlatform (framework-driven tests)."
                                }


{-| Simulate checking or unchecking a checkbox. Finds the input by its `id`
attribute and simulates a `change` event with the given checked state.

    PagesProgram.start config
        |> PagesProgram.check "agree" True
        |> PagesProgram.ensureViewHas [ Selector.text "Terms accepted" ]

-}
check : String -> Bool -> ProgramTest model msg -> ProgramTest model msg
check fieldId isChecked (ProgramTest state) =
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
                                    ("check \""
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
                                |> Event.simulate (Event.check isChecked)
                                |> Event.toResult
                    in
                    case eventResult of
                        Ok msg ->
                            applyMsgWithLabel
                                ("check \""
                                    ++ fieldId
                                    ++ "\" "
                                    ++ (if isChecked then
                                            "True"

                                        else
                                            "False"
                                       )
                                )
                                msg
                                (ProgramTest state)

                        Err errMsg ->
                            ProgramTest
                                { state
                                    | error =
                                        Just
                                            ("check \""
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

                                        newReady =
                                            { ready
                                                | model = newModel
                                                , pendingEffects = rest ++ newEffects
                                            }

                                        viewResult =
                                            newReady.getView newReady.model
                                    in
                                    ProgramTest
                                        { state
                                            | phase = Ready newReady
                                            , snapshots =
                                                state.snapshots
                                                    ++ [ makeSnapshot "resolveEffect" newReady state.modelToString ]
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



-- SNAPSHOTS


{-| Extract snapshots from a test pipeline. Each step (start, clickButton,
fillIn, resolveEffect, simulateHttp) records a snapshot of the rendered view.

If the pipeline encountered an error, a final snapshot with the error is
appended so it's visible in the test stepper.

Use this with the visual test runner to step through test execution in the
browser.

    myTest
        |> PagesProgram.toSnapshots
        |> List.map .label
        -- [ "start", "clickButton \"+1\"", "clickButton \"+1\"" ]

-}
toSnapshots : ProgramTest model msg -> List Snapshot
toSnapshots (ProgramTest state) =
    case state.error of
        Just errorMsg ->
            state.snapshots
                ++ [ { label = "ERROR"
                     , title = "Error"
                     , body = [ Html.text errorMsg ]
                     , rerender = \() -> { title = "Error", body = [ Html.text errorMsg ] }
                     , hasPendingEffects = False
                     , modelState = Nothing
                     }
                   ]

        Nothing ->
            state.snapshots


{-| Enable model state inspection in snapshots. Pass `Debug.toString` (or any
`model -> String` function) and each snapshot will include the model state.

Since published packages cannot use `Debug.toString` directly, this must be
called from your test code:

    myTest
        |> PagesProgram.withModelToString Debug.toString
        |> PagesProgram.clickButton "+1"
        |> PagesProgram.toSnapshots

-}
withModelToString : (model -> String) -> ProgramTest model msg -> ProgramTest model msg
withModelToString fn (ProgramTest state) =
    let
        updatedSnapshots =
            state.snapshots
                |> List.map
                    (\snapshot ->
                        case state.phase of
                            Ready ready ->
                                { snapshot | modelState = Just (fn ready.model) }

                            _ ->
                                snapshot
                    )
    in
    ProgramTest
        { state
            | modelToString = Just fn
            , snapshots = updatedSnapshots
        }



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
                            let
                                newState =
                                    { state | phase = newPhase }

                                simLabel =
                                    case sim of
                                        SimHttpGet url _ ->
                                            "simulateHttpGet " ++ url

                                        SimHttpPost url _ ->
                                            "simulateHttpPost " ++ url

                                snapshot =
                                    case newPhase of
                                        Ready ready ->
                                            [ makeSnapshot simLabel ready state.modelToString ]

                                        Resolving _ ->
                                            []
                            in
                            ProgramTest
                                { newState | snapshots = state.snapshots ++ snapshot }

                        AdvanceError errMsg ->
                            ProgramTest { state | error = Just errMsg }

                Ready _ ->
                    ProgramTest
                        { state
                            | error =
                                Just "No pending BackendTask to simulate. The page is already initialized."
                        }


{-| Apply a message through update, record a snapshot, and re-render.
-}
applyMsgWithLabel : String -> msg -> ProgramTest model msg -> ProgramTest model msg
applyMsgWithLabel label msg (ProgramTest state) =
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

                        newReady =
                            { ready
                                | model = newModel
                                , pendingEffects = newEffects
                            }
                    in
                    ProgramTest
                        { state
                            | phase = Ready newReady
                            , snapshots =
                                state.snapshots
                                    ++ [ makeSnapshot label newReady state.modelToString ]
                        }


makeSnapshot : String -> ReadyState model msg -> Maybe (model -> String) -> Snapshot
makeSnapshot label ready modelToString =
    let
        viewResult =
            ready.getView ready.model
    in
    { label = label
    , title = viewResult.title
    , body = (mapViewToSnapshot viewResult).body
    , rerender = \() -> mapViewToSnapshot (ready.getView ready.model)
    , hasPendingEffects = not (List.isEmpty ready.pendingEffects)
    , modelState = Maybe.map (\fn -> fn ready.model) modelToString
    }


mapViewToSnapshot : { title : String, body : List (Html msg) } -> { title : String, body : List (Html Never) }
mapViewToSnapshot v =
    -- We store body as Html Never for the snapshot viewer (non-interactive).
    -- This is safe because the viewer maps all events to NoOp anyway.
    { title = v.title, body = unsafeCoerceHtmlList v.body }


unsafeCoerceHtmlList : List (Html a) -> List (Html b)
unsafeCoerceHtmlList =
    -- elm-explorations/test uses the same trick internally.
    -- Html is a virtual-dom node; the msg type param is phantom.
    List.map (Html.map (\_ -> crashNever ()))


crashNever : () -> a
crashNever () =
    crashNever ()


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
                        , onNavigate = Nothing
                        , getBrowserUrl = Nothing
                        }

                Err err ->
                    -- BackendTask completed with FatalError
                    Ready
                        { model =
                            Tuple.first (initFn (crashData err))
                        , getView = viewFn (crashData err)
                        , update = updateFn
                        , pendingEffects = []
                        , onNavigate = Nothing
                        , getBrowserUrl = Nothing
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
    crashData (FatalError.fromString "unreachable")



-- PLATFORM HELPERS


{-| Resolve shared data, route data, and encode as ResponseSketch bytes for
Platform.FrozenViewsReady. Returns Err with a message if resolution fails.
-}
resolveInitialData config initialUrl initialPath mockResolver =
    case Pages.StaticHttpRequest.mockResolve identity config.sharedData mockResolver of
        Err sharedErr ->
            Err ("Failed to resolve Shared.template.data: " ++ fatalErrorToString sharedErr)

        Ok resolvedSharedData ->
            let
                initialRoute =
                    config.urlToRoute initialUrl
            in
            case Pages.StaticHttpRequest.mockResolve identity (config.handleRoute initialRoute) mockResolver of
                Err handleErr ->
                    Err ("Failed to resolve handleRoute: " ++ fatalErrorToString handleErr)

                Ok (Just notFoundReason) ->
                    { reason = notFoundReason
                    , path = UrlPath.fromString initialPath
                    }
                        |> ResponseSketch.NotFound
                        |> encodeResponseWithPrefix config
                        |> Ok

                Ok Nothing ->
                    case Pages.StaticHttpRequest.mockResolve identity (config.data platformTestRequest initialRoute) mockResolver of
                        Err dataErr ->
                            Err ("Failed to resolve route data: " ++ fatalErrorToString dataErr)

                        Ok (RenderPage _ pageData) ->
                            ResponseSketch.HotUpdate
                                pageData
                                resolvedSharedData
                                Nothing
                                |> encodeResponseWithPrefix config
                                |> Ok

                        Ok (ServerResponse serverResponse) ->
                            Err
                                ("Expected a rendered page but got a server response with status "
                                    ++ String.fromInt serverResponse.statusCode
                                )

                        Ok (PageServerResponse.ErrorPage _ _) ->
                            Err "Expected a rendered page but got an error page"


{-| Recursively process Platform effects. Resolves framework effects (data
fetching, navigation) synchronously using the mock resolver. User effects
are dropped (Phase 1). A depth limit prevents infinite loops.
-}
processEffects config mockResolver baseUrl model effect maxDepth =
    if maxDepth <= 0 then
        model

    else
        case effect of
            Platform.NoEffect ->
                model

            Platform.ScrollToTop ->
                model

            Platform.CancelRequest _ ->
                model

            Platform.RunCmd _ ->
                model

            Platform.UserCmd _ ->
                model

            Platform.BrowserLoadUrl _ ->
                -- External navigation not supported in tests
                model

            Platform.BrowserPushUrl path ->
                let
                    newUrl =
                        makeTestUrl baseUrl path

                    ( newModel, newEffect ) =
                        Platform.update config (Platform.UrlChanged newUrl) model
                in
                processEffects config mockResolver baseUrl newModel newEffect (maxDepth - 1)

            Platform.BrowserReplaceUrl path ->
                let
                    newUrl =
                        makeTestUrl baseUrl path

                    ( newModel, newEffect ) =
                        Platform.update config (Platform.UrlChanged newUrl) model
                in
                processEffects config mockResolver baseUrl newModel newEffect (maxDepth - 1)

            Platform.FetchFrozenViews { path } ->
                let
                    fetchUrl =
                        makeTestUrl baseUrl path

                    route =
                        config.urlToRoute fetchUrl

                    dataResult =
                        Pages.StaticHttpRequest.mockResolve identity
                            (config.data platformTestRequest route)
                            mockResolver
                in
                case dataResult of
                    Ok (RenderPage _ pageData) ->
                        let
                            encodedBytes =
                                ResponseSketch.RenderPage pageData Nothing
                                    |> encodeResponseWithPrefix config

                            ( newModel, newEffect ) =
                                Platform.update config
                                    (Platform.FrozenViewsReady (Just encodedBytes))
                                    model
                        in
                        processEffects config mockResolver baseUrl newModel newEffect (maxDepth - 1)

                    _ ->
                        -- Data resolution failed during navigation; leave model unchanged
                        model

            Platform.Submit _ ->
                -- TODO: Phase 2 - form submissions
                model

            Platform.SubmitFetcher _ _ _ ->
                -- TODO: Phase 5 - concurrent submissions
                model

            Platform.Batch effects ->
                List.foldl
                    (\eff m ->
                        processEffects config mockResolver baseUrl m eff (maxDepth - 1)
                    )
                    model
                    effects


{-| Construct a test URL from a base URL and path.
-}
makeTestUrl : String -> String -> Url
makeTestUrl baseUrl path =
    let
        fullUrl =
            if String.startsWith "http" path then
                path

            else
                baseUrl ++ path
    in
    case Url.fromString fullUrl of
        Just url ->
            url

        Nothing ->
            -- Fallback: construct URL manually
            { protocol = Url.Https
            , host = "localhost"
            , port_ = Just 1234
            , path = path
            , query = Nothing
            , fragment = Nothing
            }


{-| A fake incoming HTTP request for data resolution in tests.
-}
platformTestRequest : Internal.Request.Request
platformTestRequest =
    Internal.Request.Request
        { time = Time.millisToPosix 0
        , method = "GET"
        , body = Nothing
        , rawUrl = "http://localhost:1234/"
        , rawHeaders = Dict.empty
        , cookies = Dict.empty
        }


{-| Encode a ResponseSketch with the frozen views prefix that decodeResponse
expects. The prefix is a 4-byte big-endian length (0) indicating zero bytes
of frozen view data to skip.
-}
encodeResponseWithPrefix config sketch =
    Bytes.Encode.encode
        (Bytes.Encode.sequence
            [ Bytes.Encode.unsignedInt32 Bytes.BE 0
            , config.encodeResponse sketch
            ]
        )


fatalErrorToString : FatalError -> String
fatalErrorToString err =
    case err of
        Pages.Internal.FatalError.FatalError info ->
            info.title ++ ": " ++ info.body
