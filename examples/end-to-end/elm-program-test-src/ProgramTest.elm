module ProgramTest exposing
    ( ProgramTest, start
    , createSandbox, createElement, createDocument, createApplication, createWorker
    , ProgramDefinition
    , withBaseUrl, withJsonStringFlags
    , withSimulatedEffects, SimulatedEffect, SimulatedTask
    , withSimulatedSubscriptions, SimulatedSub
    , done
    , expectViewHas, expectViewHasNot, expectView
    , ensureViewHas, ensureViewHasNot, ensureView
    , clickButton, clickLink
    , fillIn, fillInTextarea
    , check, selectOption
    , simulateDomEvent
    , within
    , expectHttpRequestWasMade, expectHttpRequest, expectHttpRequests
    , ensureHttpRequestWasMade, ensureHttpRequest, ensureHttpRequests
    , simulateHttpOk, simulateHttpResponse, simulateHttpResponseAdvanced
    , advanceTime
    , expectOutgoingPortValues, ensureOutgoingPortValues
    , simulateIncomingPort
    , expectPageChange, expectBrowserUrl, expectBrowserHistory
    , ensureBrowserUrl, ensureBrowserHistory
    , routeChange
    , update
    , expectModel
    , expectLastEffect, ensureLastEffect
    , simulateLastEffect
    , fail, createFailed
    , getOutgoingPortValues
    , SimpleState, fillInDom, onFormSubmit, updateCookieJar
    )

{-| A `ProgramTest` simulates the execution of an Elm program
enabling you write high-level tests for your program.
(Testing your programs at this level
provides test coverage that is resilient even to drastic refactorings of your application architecture,
and encourages tests that make it clear how end-users and external services will interact with your program.)

This module allows you to interact with your program by simulating
user interactions and external events (like HTTP responses and ports),
and making assertions about the HTML it renders and the external requests it makes.

  - [Guide for upgrading from elm-program-test 2.x to 3.x](https://elm-program-test.netlify.com/upgrade-3.0.0.html)


## Documentation index

The list below is an index into the API documentation for the
assertion and simulation functions relevant to each topic:

  - creating tests: [creating](#creating-program-definitions) &mdash; [starting](#start) &mdash; [options](#options)
  - **HTML**: [assertions](#inspecting-html) &mdash; [simulating user input](#simulating-user-input)
  - **HTTP**: [assertions](#inspecting-http-requests) &mdash; [simulating responses](#simulating-http-responses)
  - **time**: [simulating the passing of time](#simulating-time)
  - **ports**: [assertions](#inspecting-outgoing-ports) &mdash; [simulating incoming ports](#simulating-incoming-ports)
  - **browser**: [assertions](#browser-assertions) &mdash; [simulating](#simulating-browser-interactions)


## Getting started

For a more detailed explanation of how to get started,
see the elm-program-test guidebooks
(the best one to start with is “Testing programs with interactive views”):

  - [Testing programs with interactive views](https://elm-program-test.netlify.com//html.html) &mdash;
    shows an example of test-driving adding form validation to an Elm program
  - [Testing programs with Cmds](https://elm-program-test.netlify.com/cmds.html) &mdash; shows testing a program
    that uses `Http.get` and `Http.post`
  - [Testing programs with ports](https://elm-program-test.netlify.com/ports.html) &mdash; shows testing a program
    that uses ports to interface with JavaScript


# Creating

@docs ProgramTest, start


## Creating program definitions

A `ProgramDefinition` (required to create a `ProgramTest` with [`start`](#start))
can be created with one of the following functions that parallel
the functions in [`elm/browser`](https://package.elm-lang.org/packages/elm/browser/latest/Browser) for creating programs.

@docs createSandbox, createElement, createDocument, createApplication, createWorker
@docs ProgramDefinition


## Options

The following functions allow you to configure your
`ProgramDefinition` before starting it with [`start`](#start).

@docs withBaseUrl, withJsonStringFlags

@docs withSimulatedEffects, SimulatedEffect, SimulatedTask
@docs withSimulatedSubscriptions, SimulatedSub


## Ending a test

@docs done


# Inspecting and interacting with HTML


## Inspecting HTML

@docs expectViewHas, expectViewHasNot, expectView
@docs ensureViewHas, ensureViewHasNot, ensureView


## Simulating user input

@docs clickButton, clickLink
@docs fillIn, fillInTextarea
@docs check, selectOption


## Simulating user input (advanced)

@docs simulateDomEvent
@docs within


# Inspecting and simulating HTTP requests and responses


# Inspecting HTTP requests

@docs expectHttpRequestWasMade, expectHttpRequest, expectHttpRequests
@docs ensureHttpRequestWasMade, ensureHttpRequest, ensureHttpRequests


## Simulating HTTP responses

@docs simulateHttpOk, simulateHttpResponse, simulateHttpResponseAdvanced


# Simulating time

@docs advanceTime


# Inspecting and simulating ports


## Inspecting outgoing ports

@docs expectOutgoingPortValues, ensureOutgoingPortValues


## Simulating incoming ports

@docs simulateIncomingPort


# Browser navigation


## Browser assertions

@docs expectPageChange, expectBrowserUrl, expectBrowserHistory
@docs ensureBrowserUrl, ensureBrowserHistory


## Simulating browser interactions

@docs routeChange


# Low-level functions

You should avoid the functions below when possible,
but you may find them useful to test things that are not yet directly supported by elm-program-test.


## Low-level functions for Msgs and Models

@docs update
@docs expectModel


## Low-level functions for effects

@docs expectLastEffect, ensureLastEffect
@docs simulateLastEffect


## Custom assertions

These functions may be useful if you are writing your own custom assertion functions.

@docs fail, createFailed
@docs getOutgoingPortValues

-}

import Browser
import Dict exposing (Dict)
import Expect exposing (Expectation)
import Html exposing (Html)
import Html.Attributes exposing (attribute)
import Http
import Json.Decode
import Json.Encode
import List.Extra
import MultiDict
import ProgramTest.ComplexQuery as ComplexQuery exposing (ComplexQuery)
import ProgramTest.EffectSimulation as EffectSimulation exposing (EffectSimulation)
import ProgramTest.Failure as Failure exposing (Failure(..))
import ProgramTest.Program as Program exposing (Program)
import SimulatedEffect exposing (SimulatedEffect, SimulatedSub, SimulatedTask)
import String.Extra
import Test.Html.Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector exposing (Selector)
import Test.Http
import Test.Runner
import TestResult exposing (TestResult)
import TestState exposing (TestState)
import Url exposing (Url)


{-| A `ProgramTest` represents an Elm program,
a current state for that program,
information about external effects that have been produced by the program (such as pending HTTP requests, values sent to outgoing ports, etc),
and a log of any errors that have occurred while simulating interaction with the program.

  - To create a `ProgramTest`, see the `create*` functions below.
  - To advance the state of a `ProgramTest`, see [Simulating user input](#simulating-user-input), or the many simulate functions in this module.
  - To assert on the resulting state of a `ProgramTest`, see the many `expect*` functions in this module.

-}
type ProgramTest model msg effect
    = Created
        { program : Program model msg effect (SimulatedSub msg)
        , state : TestResult model msg effect
        }
    | FailedToCreate Failure


onFormSubmit : ProgramTest model msg effect -> Maybe (Dict String String -> effect)
onFormSubmit programTest =
    case programTest of
        Created { program } ->
            program.onFormSubmit

        _ ->
            Nothing


andThen :
    (Program model msg effect (SimulatedSub msg) -> TestState model msg effect -> Result Failure (TestState model msg effect))
    -> ProgramTest model msg effect
    -> ProgramTest model msg effect
andThen f programTest =
    case programTest of
        Created created ->
            Created
                { created
                    | state = TestResult.andThen (f created.program) created.state
                }

        FailedToCreate failure ->
            FailedToCreate failure


toFailure : ProgramTest model msg effect -> Maybe Failure
toFailure programTest =
    case programTest of
        Created created ->
            case created.state of
                Err f ->
                    Just f.reason

                Ok _ ->
                    Nothing

        FailedToCreate f ->
            Just f


type alias TestLog model msg =
    { view : model -> Html msg
    , history : List model
    }


type alias ProgramOptions model msg effect =
    { baseUrl : Maybe Url
    , deconstructEffect : Maybe (SimpleState -> effect -> ( Dict String String, SimulatedEffect msg ))
    , subscriptions : Maybe (model -> SimulatedSub msg)
    }


emptyOptions : ProgramOptions model msg effect
emptyOptions =
    { baseUrl = Nothing
    , deconstructEffect = Nothing
    , subscriptions = Nothing
    }


{-| Represents an unstarted program test.
Use [`start`](#start) to start the program being tested.
-}
type ProgramDefinition flags model msg effect
    = ProgramDefinition (ProgramOptions model msg effect) (Maybe Url -> flags -> ProgramOptions model msg effect -> ProgramTest model msg effect)


createHelper :
    { init : ( model, effect )
    , update : msg -> model -> ( model, effect )
    , view : model -> Html msg
    , onRouteChange : Url -> Maybe msg
    , onFormSubmit : Maybe (Dict String String -> effect)
    }
    -> ProgramOptions model msg effect
    -> ProgramTest model msg effect
createHelper program options =
    let
        program_ =
            { update = program.update
            , view = program.view
            , onRouteChange = program.onRouteChange
            , subscriptions = options.subscriptions
            , withinFocus = identity
            , onFormSubmit = program.onFormSubmit
            }

        ( newModel, newEffect ) =
            program.init
    in
    Created
        { program = program_
        , state =
            Ok
                -- TODO: move to TestState.init after pulling deconstructEffect out of EffectSimulation
                { currentModel = newModel
                , lastEffect = newEffect
                , navigation =
                    case options.baseUrl of
                        Nothing ->
                            Nothing

                        Just baseUrl ->
                            Just
                                { currentLocation = baseUrl
                                , browserHistory = []
                                }
                , effectSimulation = Maybe.map EffectSimulation.init options.deconstructEffect
                , domFields = Dict.empty
                , cookieJar = Dict.empty
                }
        }
        |> andThen
            (\_ ->
                TestState.queueEffect program_ newEffect
                    >> Result.andThen (TestState.drain program_)
            )


{-| Creates a `ProgramDefinition` from the parts of a [`Browser.sandbox`](https://package.elm-lang.org/packages/elm/browser/latest/Browser#sandbox) program.

See other `create*` functions below if the program you want to test does not use `Browser.sandbox`.

-}
createSandbox :
    { init : model
    , view : model -> Html msg
    , update : msg -> model -> model
    }
    -> ProgramDefinition () model msg ()
createSandbox program =
    ProgramDefinition emptyOptions <|
        \_ () ->
            createHelper
                { init = ( program.init, () )
                , update = \msg model -> ( program.update msg model, () )
                , view = program.view
                , onRouteChange = \_ -> Nothing
                , onFormSubmit = Nothing
                }


{-| Creates a `ProgramTest` from the parts of a [`Platform.worker`](https://package.elm-lang.org/packages/elm/core/latest/Platform#worker) program.

See other `create*` functions if the program you want to test does not use `Platform.worker`.

If your program has subscriptions that you want to simulate, see [`withSimulatedSubscriptions`](#withSimulatedSubscriptions).

-}
createWorker :
    { init : flags -> ( model, effect )
    , update : msg -> model -> ( model, effect )
    }
    -> ProgramDefinition flags model msg effect
createWorker program =
    ProgramDefinition emptyOptions <|
        \_ flags ->
            createHelper
                { init = program.init flags
                , update = program.update
                , view = \_ -> Html.text "** Programs created with ProgramTest.createWorker do not have a view.  Use ProgramTest.createElement instead if you meant to provide a view function. **"
                , onRouteChange = \_ -> Nothing
                , onFormSubmit = Nothing
                }


{-| Creates a `ProgramTest` from the parts of a [`Browser.element`](https://package.elm-lang.org/packages/elm/browser/latest/Browser#element) program.

See other `create*` functions below if the program you want to test does not use `Browser.element`.

If your program has subscriptions that you want to simulate, see [`withSimulatedSubscriptions`](#withSimulatedSubscriptions).

-}
createElement :
    { init : flags -> ( model, effect )
    , view : model -> Html msg
    , update : msg -> model -> ( model, effect )
    }
    -> ProgramDefinition flags model msg effect
createElement program =
    ProgramDefinition emptyOptions <|
        \_ flags ->
            createHelper
                { init = program.init flags
                , update = program.update
                , view = program.view
                , onRouteChange = \_ -> Nothing
                , onFormSubmit = Nothing
                }


{-| Starts the given test program by initializing it with the given flags.

If your program uses `Json.Encode.Value` as its flags type,
you may find [`withJsonStringFlags`](#withJsonStringFlags) useful.

-}
start : flags -> ProgramDefinition flags model msg effect -> ProgramTest model msg effect
start flags (ProgramDefinition options program) =
    program options.baseUrl flags options


{-| Sets the initial browser URL

You must set this when using `createApplication`,
or when using [`clickLink`](#clickLink) and [`expectPageChange`](#expectPageChange)
to simulate a user clicking a link with relative URL.

-}
withBaseUrl : String -> ProgramDefinition flags model msg effect -> ProgramDefinition flags model msg effect
withBaseUrl baseUrl (ProgramDefinition options program) =
    case Url.fromString baseUrl of
        Nothing ->
            ProgramDefinition options
                (\_ _ _ ->
                    FailedToCreate (InvalidLocationUrl "withBaseUrl" baseUrl)
                )

        Just url ->
            ProgramDefinition { options | baseUrl = Just url } program


{-| Provides a convenient way to provide flags for a program that decodes flags from JSON.
By providing the JSON decoder, you can then provide the flags as a JSON string when calling
[`start`](#start).
-}
withJsonStringFlags :
    Json.Decode.Decoder flags
    -> ProgramDefinition flags model msg effect
    -> ProgramDefinition String model msg effect
withJsonStringFlags decoder (ProgramDefinition options program) =
    ProgramDefinition options <|
        \location json ->
            case Json.Decode.decodeString decoder json of
                Ok flags ->
                    program location flags

                Err message ->
                    \_ ->
                        FailedToCreate (InvalidFlags "withJsonStringFlags" (Json.Decode.errorToString message))


{-| This allows you to provide a function that lets `ProgramTest` simulate effects that would become `Cmd`s and `Task`s
when your app runs in production
(this enables you to use [`simulateHttpResponse`](#simulateHttpResponse), [`advanceTime`](#advanceTime), etc.).
For a detailed explanation and example of how to set up tests that use simulated effects,
see the [“Testing programs with Cmds” guidebook](https://elm-program-test.netlify.com/cmds.html).

You only need to use this if you need to simulate [HTTP requests](#simulating-http-responses),
[outgoing ports](#expectOutgoingPortValues),
or the [passing of time](#simulating-time).

See the `SimulatedEffect.*` modules in this package for functions that you can use to implement
the required `effect -> SimulatedEffect msg` function for your `effect` type.

-}
withSimulatedEffects :
    (SimpleState -> effect -> ( Dict String String, SimulatedEffect msg ))
    -> ProgramDefinition flags model msg effect
    -> ProgramDefinition flags model msg effect
withSimulatedEffects fn (ProgramDefinition options program) =
    ProgramDefinition { options | deconstructEffect = Just fn } program


type alias SimpleState =
    { navigation :
        Maybe
            { currentLocation : Url
            , browserHistory : List Url
            }
    , domFields : Dict String String
    , cookieJar : Dict String String
    }


{-| This allows you to provide a function that lets `ProgramTest` simulate subscriptions that would be `Sub`s
when your app runs in production
(this enables you to use [`simulateIncomingPort`](#simulateIncomingPort), etc.).
You only need to use this if you need to simulate subscriptions in your test.
For a detailed explanation and example of how to set up tests that use simulated subscriptions,
see the [“Testing programs with ports” guidebook](https://elm-program-test.netlify.com/ports.html).

The function you provide should be similar to your program's `subscriptions` function
but return `SimulatedSub`s instead of `Sub`s.
See the `SimulatedEffect.*` modules in this package for functions that you can use to implement
the required `model -> SimulatedSub msg` function.

-}
withSimulatedSubscriptions :
    (model -> SimulatedSub msg)
    -> ProgramDefinition flags model msg effect
    -> ProgramDefinition flags model msg effect
withSimulatedSubscriptions fn (ProgramDefinition options program) =
    ProgramDefinition { options | subscriptions = Just fn } program


{-| Creates a `ProgramTest` from the parts of a [`Browser.document`](https://package.elm-lang.org/packages/elm/browser/latest/Browser#document) program.

See other `create*` functions if the program you want to test does not use `Browser.document`.

If your program has subscriptions that you want to simulate, see [`withSimulatedSubscriptions`](#withSimulatedSubscriptions).

-}
createDocument :
    { init : flags -> ( model, effect )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, effect )
    }
    -> ProgramDefinition flags model msg effect
createDocument program =
    ProgramDefinition emptyOptions <|
        \_ flags ->
            createHelper
                { init = program.init flags
                , update = program.update
                , view = \model -> Html.node "body" [] (program.view model).body
                , onRouteChange = \_ -> Nothing
                , onFormSubmit = Nothing
                }


{-| Creates a `ProgramTest` from the parts of a [`Browser.application`](https://package.elm-lang.org/packages/elm/browser/latest/Browser#application) program.

See other `create*` functions if the program you want to test does not use `Browser.application`.

If your program has subscriptions that you want to simulate, see [`withSimulatedSubscriptions`](#withSimulatedSubscriptions).

Note that Elm currently does not provide any way to create a [`Browser.Navigation.Key`](https://package.elm-lang.org/packages/elm/browser/latest/Browser-Navigation#Key) in tests, so this function uses `()` as the key type instead.
For an example of how to test such a program, see
[NavigationKeyExample.elm](https://github.com/avh4/elm-program-test/blob/main/examples/src/NavigationKeyExample.elm)
and [NavigationKeyExampleTest.elm](https://github.com/avh4/elm-program-test/blob/main/examples/tests/NavigationKeyExampleTest.elm).

-}
createApplication :
    { init : flags -> Url -> () -> ( model, effect )
    , view : model -> Browser.Document msg
    , update : msg -> model -> ( model, effect )
    , onUrlRequest : Browser.UrlRequest -> msg
    , onUrlChange : Url -> msg
    , onFormSubmit : Dict String String -> effect
    }
    -> ProgramDefinition flags model msg effect
createApplication program =
    ProgramDefinition emptyOptions <|
        \location flags ->
            case location of
                Nothing ->
                    \_ ->
                        FailedToCreate (NoBaseUrl "createApplication" "")

                Just url ->
                    createHelper
                        { init = program.init flags url ()
                        , update = program.update
                        , view = \model -> Html.node "body" [] (program.view model).body
                        , onRouteChange = program.onUrlChange >> Just
                        , onFormSubmit = Just program.onFormSubmit
                        }


{-| This represents an effect that elm-program-test is able to simulate.
When using [`withSimulatedEffects`](#withSimulatedEffects) you will provide a function that can translate
your program's effects into `SimulatedEffect`s.
(If you do not use `withSimulatedEffects`,
then `ProgramTest` will not simulate any effects for you.)

You can create `SimulatedEffect`s using the following modules,
which parallel the modules your real program would use to create `Cmd`s and `Task`s:

  - [`SimulatedEffect.Http`](SimulatedEffect-Http) (parallels `Http` from `elm/http`)
  - [`SimulatedEffect.Cmd`](SimulatedEffect-Cmd) (parallels `Platform.Cmd` from `elm/core`)
  - [`SimulatedEffect.Navigation`](SimulatedEffect-Navigation) (parallels `Browser.Navigation` from `elm/browser`)
  - [`SimulatedEffect.Ports`](SimulatedEffect-Ports) (parallels the `port` keyword)
  - [`SimulatedEffect.Task`](SimulatedEffect-Task) (parallels `Task` from `elm/core`)
  - [`SimulatedEffect.Process`](SimulatedEffect-Process) (parallels `Process` from `elm/core`)
  - [`SimulatedEffect.Time`](SimulatedEffect-Time) (parallels `Time` from `elm/time`)

-}
type alias SimulatedEffect msg =
    SimulatedEffect.SimulatedEffect msg


{-| Similar to `SimulatedEffect`, but represents a `Task` instead of a `Cmd`.
-}
type alias SimulatedTask x a =
    SimulatedEffect.SimulatedTask x a


{-| This represents a subscription that elm-program-test is able to simulate.
When using [`withSimulatedSubscriptions`](#withSimulatedSubscriptions) you will provide
a function that is similar to your program's `subscriptions` function but that
returns `SimulatedSub`s instead `Sub`s.
(If you do not use `withSimulatedSubscriptions`,
then `ProgramTest` will not simulate any subscriptions for you.)

You can create `SimulatedSub`s using the following modules:

  - [`SimulatedEffect.Ports`](SimulatedEffect-Ports) (parallels the `port` keyword)

-}
type alias SimulatedSub msg =
    SimulatedEffect.SimulatedSub msg


{-| Advances the state of the `ProgramTest` by applying the given `msg` to your program's update function
(provided when you created the `ProgramTest`).

This can be used to simulate events that can only be triggered by [commands (`Cmd`) and subscriptions (`Sub`)](https://guide.elm-lang.org/architecture/effects/)
(i.e., that cannot be triggered by user interaction with the view).

NOTE: When possible, you should prefer [Simulating user input](#simulating-user-input),
[Simulating HTTP responses](#simulating-http-responses),
or (if neither of those support what you need) [`simulateLastEffect`](#simulateLastEffect),
as doing so will make your tests more resilient to changes in your program's implementation details.

-}
update : msg -> ProgramTest model msg effect -> ProgramTest model msg effect
update msg =
    andThen (TestState.update msg)


{-| DEPRECATED: use `simulateComplexQuery` instead
-}
simulateHelper :
    String
    -> (Query.Single msg -> Query.Single msg)
    -> ( String, Json.Encode.Value )
    -> Program model msg effect sub
    -> TestState model msg effect
    -> Result Failure (TestState model msg effect)
simulateHelper functionDescription findTarget event program state =
    let
        targetQuery =
            Program.renderView program state.currentModel
                |> findTarget
    in
    -- First check the target so we can give a better error message if it doesn't exist
    case
        targetQuery
            |> Query.has []
            |> Test.Runner.getFailureReason
    of
        Just reason ->
            Err (SimulateFailedToFindTarget functionDescription reason.description)

        Nothing ->
            -- Try to simulate the event, now that we know the target exists
            case
                targetQuery
                    |> Test.Html.Event.simulate event
                    |> Test.Html.Event.toResult
            of
                Err message ->
                    Err (SimulateFailed functionDescription message)

                Ok msg ->
                    TestState.update msg program state


{-| **PRIVATE** helper for simulating events on input elements with associated labels.

NOTE: Currently, this function requires that you also provide the field id
(which must match both the `id` attribute of the target `input` element,
and the `for` attribute of the `label` element).
After [eeue56/elm-html-test#52](https://github.com/eeue56/elm-html-test/issues/52) is resolved,
a future release of this package will remove the `fieldId` parameter.

-}
simulateLabeledInputHelper : String -> String -> String -> Bool -> List Selector -> ( String, Json.Encode.Value ) -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateLabeledInputHelper functionDescription fieldId label allowTextArea additionalInputSelectors event =
    let
        associatedLabel : List Selector
        associatedLabel =
            [ Selector.tag "label"
            , Selector.attribute (Html.Attributes.for fieldId)
            , Selector.text label
            ]

        checks =
            if allowTextArea then
                checks_ "input" ++ checks_ "textarea"

            else
                checks_ "input"

        --checks_ : String -> List ( String, ComplexQuery (Query.Single msg) -> ComplexQuery msg )
        checks_ : String -> List ( String, ComplexQuery (Query.Single msg) -> ComplexQuery (Query.Single msg) )
        checks_ inputTag =
            if fieldId == "" then
                [ ( "<" ++ inputTag ++ "> with parent <label>"
                  , ComplexQuery.find (Just "find label")
                        [ "label" ]
                        [ Selector.tag "label"
                        , Selector.containing [ Selector.text label ]
                        ]
                        >> ComplexQuery.find Nothing
                            [ inputTag ]
                            [ Selector.tag inputTag ]
                    -->> ComplexQuery.simulate event
                  )
                , ( "<" ++ inputTag ++ "> with aria-label"
                  , ComplexQuery.find Nothing
                        [ inputTag ]
                        [ Selector.tag inputTag
                        , Selector.attribute (attribute "aria-label" label)
                        ]
                    -->> ComplexQuery.succeed identity
                  )
                ]

            else
                [ ( "<" ++ inputTag ++ "> associated to <label> by id"
                  , ComplexQuery.check "check label exists"
                        (ComplexQuery.find Nothing [ "label" ] associatedLabel)
                        >> ComplexQuery.find (Just ("find " ++ inputTag))
                            [ inputTag ]
                            (List.concat
                                [ [ Selector.tag inputTag
                                  , Selector.id fieldId
                                  ]
                                , additionalInputSelectors
                                ]
                            )
                    -->> ComplexQuery.simulate event
                  )
                , ( "<" ++ inputTag ++ "> with aria-label and id"
                  , ComplexQuery.find Nothing
                        [ inputTag ]
                        [ Selector.tag inputTag
                        , Selector.id fieldId
                        , Selector.attribute (attribute "aria-label" label)
                        ]
                    -->> ComplexQuery.simulate event
                  )
                ]
    in
    -- TODO this is currently skipping event handler simulation. Need to make it *optional* (so form submit without event handlers works as well and stores DOM input state instead of Elm input state).
    --simulateComplexQuery functionDescription
    --    (ComplexQuery.exactlyOneOf
    --        ("Expected one of the following to exist and have an " ++ String.Extra.escape ("on" ++ Tuple.first event) ++ " handler")
    --        checks
    --    )
    assertComplexQuery functionDescription
        (ComplexQuery.exactlyOneOf
            ("Expected one of the following to exist and have an " ++ String.Extra.escape ("on" ++ Tuple.first event) ++ " handler")
            checks
        )


{-| TODO: have other internal functions use this to have more consistent error message.
-}
simulateComplexQuery : String -> (ComplexQuery (Query.Single msg) -> ComplexQuery msg) -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateComplexQuery functionName complexQuery =
    andThen <|
        \program state ->
            let
                view =
                    Program.renderView program state.currentModel
            in
            case ComplexQuery.run (complexQuery (ComplexQuery.succeed view)) of
                ( _, Ok msg ) ->
                    TestState.update msg program state

                ( highlight, Err queryFailure ) ->
                    Err (ViewAssertionFailed ("ProgramTest." ++ functionName) (Html.map (\_ -> ()) (program.view state.currentModel)) highlight queryFailure)


{-| -}
simulateComplexQueryOrSubmit : String -> (ComplexQuery (Query.Single msg) -> ComplexQuery (ComplexQuery.MsgOrSubmit msg)) -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateComplexQueryOrSubmit functionName complexQuery programTest =
    andThen
        (\program state ->
            let
                view =
                    Program.renderView program state.currentModel
            in
            case ComplexQuery.run (complexQuery (ComplexQuery.succeed view)) of
                ( _, Ok (ComplexQuery.SubmitMsg msg) ) ->
                    TestState.update msg program state

                ( _, Ok ComplexQuery.Submit ) ->
                    submitFormInner programTest program state

                ( highlight, Err queryFailure ) ->
                    Err (ViewAssertionFailed ("ProgramTest." ++ functionName) (Html.map (\_ -> ()) (program.view state.currentModel)) highlight queryFailure)
        )
        programTest


assertComplexQuery : String -> (ComplexQuery (Query.Single msg) -> ComplexQuery ignored) -> ProgramTest model msg effect -> ProgramTest model msg effect
assertComplexQuery functionName complexQuery =
    andThen <|
        \program state ->
            let
                view =
                    Program.renderView program state.currentModel
            in
            case ComplexQuery.run (complexQuery (ComplexQuery.succeed view)) of
                ( _, Ok _ ) ->
                    Ok state

                ( highlight, Err queryFailure ) ->
                    Err (ViewAssertionFailed ("ProgramTest." ++ functionName) (Html.map (\_ -> ()) (program.view state.currentModel)) highlight queryFailure)


{-| Simulates a custom DOM event.

NOTE: If there is another, more specific function (see [“Simulating user input”](#simulating-user-input))
that does what you want, prefer that instead, as you will get the benefit of better error messages.

The parameters are:

1.  A function to find the HTML element that responds to the event
    (typically this will be a call to `Test.Html.Query.find [ ...some selector... ]`)
2.  The event to simulate
    (see [Test.Html.Event "Event Builders"](https://package.elm-lang.org/packages/elm-explorations/test/latest/Test-Html-Event#event-builders))

-}
simulateDomEvent : (Query.Single msg -> Query.Single msg) -> ( String, Json.Encode.Value ) -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateDomEvent findTarget ( eventName, eventValue ) =
    andThen (simulateHelper ("simulateDomEvent " ++ String.Extra.escape eventName) findTarget ( eventName, eventValue ))


submitFormInner : ProgramTest model msg effect -> Program model msg effect sub -> TestState model msg effect -> Result Failure (TestState model msg effect)
submitFormInner programTest state testState =
    case onFormSubmit programTest of
        Just onFormSubmitFn ->
            testState
                |> TestState.queueEffect state
                    (onFormSubmitFn
                        testState.domFields
                    )
                |> Result.andThen (TestState.drain state)

        Nothing ->
            Ok testState


{-| Simulates clicking a button.

This function will find and click a `<button>` HTML node containing the given `buttonText`.

It will also try to find and click elements with the accessibility label `role="button"`.

If the button is disabled the test will fail.

-}
clickButton : String -> ProgramTest model msg effect -> ProgramTest model msg effect
clickButton buttonText =
    let
        functionDescription =
            "clickButton " ++ String.Extra.escape buttonText

        checks : List ( String, ComplexQuery (Query.Single msg) -> ComplexQuery (ComplexQuery.MsgOrSubmit msg) )
        checks =
            [ ( "<button> with text"
              , findNotDisabled (Just "find button")
                    [ "button" ]
                    Nothing
                    [ Selector.tag "button"
                    , Selector.containing [ Selector.text buttonText ]
                    ]
                    >> ComplexQuery.simulate Test.Html.Event.click
                    >> ComplexQuery.map ComplexQuery.SubmitMsg
              )
            , ( "<button> with <img> with alt text"
              , findNotDisabled (Just "find button")
                    [ "button" ]
                    Nothing
                    [ Selector.tag "button"
                    , Selector.containing
                        [ Selector.tag "img"
                        , Selector.attribute (Html.Attributes.alt buttonText)
                        ]
                    ]
                    >> ComplexQuery.simulate Test.Html.Event.click
                    >> ComplexQuery.map ComplexQuery.SubmitMsg
              )
            , ( "<button> with aria-label"
              , findNotDisabled (Just "find button")
                    [ "button" ]
                    Nothing
                    [ Selector.tag "button"
                    , Selector.attribute (Html.Attributes.attribute "aria-label" buttonText)
                    ]
                    >> ComplexQuery.simulate Test.Html.Event.click
                    >> ComplexQuery.map ComplexQuery.SubmitMsg
              )
            , ( "any element with role=\"button\" and text"
              , findNotDisabled (Just "find button")
                    [ "button" ]
                    (Just
                        [ Selector.all
                            [ Selector.tag "button"
                            , Selector.attribute (Html.Attributes.attribute "role" "button")
                            ]
                        ]
                    )
                    [ Selector.attribute (Html.Attributes.attribute "role" "button")
                    , Selector.containing [ Selector.text buttonText ]
                    ]
                    >> ComplexQuery.simulate Test.Html.Event.click
                    >> ComplexQuery.map ComplexQuery.SubmitMsg
              )
            , ( "any element with role=\"button\" and aria-label"
              , findNotDisabled (Just "find button")
                    [ "button" ]
                    (Just
                        [ Selector.all
                            [ Selector.tag "button"
                            , Selector.attribute (Html.Attributes.attribute "role" "button")
                            ]
                        ]
                    )
                    [ Selector.attribute (Html.Attributes.attribute "role" "button")
                    , Selector.attribute (Html.Attributes.attribute "aria-label" buttonText)
                    ]
                    >> ComplexQuery.simulate Test.Html.Event.click
                    >> ComplexQuery.map ComplexQuery.SubmitMsg
              )
            , ( "<form> with submit <button> with text"
              , ComplexQuery.findButNot (Just "find form")
                    [ "form" ]
                    { good =
                        [ Selector.tag "form"
                        , Selector.containing
                            [ Selector.tag "button"
                            , Selector.containing [ Selector.text buttonText ]
                            ]
                        ]
                    , bads =
                        [ [ Selector.tag "form"
                          , Selector.containing
                                [ Selector.tag "button"
                                , Selector.attribute (Html.Attributes.type_ "button")
                                , Selector.containing [ Selector.text buttonText ]
                                ]
                          ]
                        , [ Selector.tag "form"
                          , Selector.containing
                                [ Selector.tag "button"
                                , Selector.attribute (Html.Attributes.disabled True)
                                , Selector.containing [ Selector.text buttonText ]
                                ]
                          ]
                        ]
                    , onError =
                        [ Selector.tag "form"
                        , Selector.containing
                            [ Selector.tag "button"
                            , Selector.attribute (Html.Attributes.disabled False)
                            , Selector.attribute (Html.Attributes.type_ "submit")
                            , Selector.containing [ Selector.text buttonText ]
                            ]
                        ]
                    }
                    >> ComplexQuery.simulateSubmit
              )
            , ( "<form> with submit <input> with value"
              , ComplexQuery.findButNot (Just "find form")
                    [ "form" ]
                    { good =
                        [ Selector.tag "form"
                        , Selector.containing
                            [ Selector.tag "input"
                            , Selector.attribute (Html.Attributes.type_ "submit")
                            , Selector.attribute (Html.Attributes.value buttonText)
                            ]
                        ]
                    , bads =
                        [ [ Selector.tag "form"
                          , Selector.containing
                                [ Selector.tag "input"
                                , Selector.attribute (Html.Attributes.type_ "submit")
                                , Selector.attribute (Html.Attributes.disabled True)
                                , Selector.attribute (Html.Attributes.value buttonText)
                                ]
                          ]
                        ]
                    , onError =
                        [ Selector.tag "form"
                        , Selector.containing
                            [ Selector.tag "input"
                            , Selector.attribute (Html.Attributes.type_ "submit")
                            , Selector.attribute (Html.Attributes.disabled False)
                            , Selector.attribute (Html.Attributes.value buttonText)
                            ]
                        ]
                    }
                    >> ComplexQuery.simulateSubmit
              )
            ]
    in
    simulateComplexQueryOrSubmit functionDescription
        (ComplexQuery.exactlyOneOf "Expected one of the following to exist" checks)


findNotDisabled : Maybe String -> List String -> Maybe (List Selector) -> List Selector -> ComplexQuery (Query.Single msg) -> ComplexQuery (Query.Single msg)
findNotDisabled description highlight additionalBad selectors =
    -- This is tricky because Test.Html doesn't provide a way to search for an attribute being *not* present.
    -- So we have to check if "disabled=True" *is* present, and manually force a failure if it is.
    -- (We can't just search for "disabled=False" because we need to allow elements that don't specify "disabled" at all.)
    ComplexQuery.findButNot description
        highlight
        { good = selectors
        , bads =
            List.filterMap identity
                [ Just (Selector.disabled True :: selectors)
                , additionalBad
                ]
        , onError = selectors ++ [ Selector.disabled False ]
        }


{-| Simulates clicking a `<a href="...">` link.

The parameters are:

1.  The text of the `<a>` tag (which is the link text visible to the user).

2.  The `href` of the `<a>` tag.

    NOTE: After [eeue56/elm-html-test#52](https://github.com/eeue56/elm-html-test/issues/52) is resolved,
    a future release of this package will remove the `href` parameter.

Note for testing single-page apps:
if the target `<a>` tag has an `onClick` handler,
then the message produced by the handler will be processed
and the `href` will not be followed.
NOTE: Currently this function cannot verify that the onClick handler
sets `preventDefault`, but this will be done in the future after
<https://github.com/eeue56/elm-html-test/issues/63> is resolved.

-}
clickLink : String -> String -> ProgramTest model msg effect -> ProgramTest model msg effect
clickLink linkText href programTest =
    let
        functionDescription =
            "clickLink " ++ String.Extra.escape linkText

        findLinkTag =
            [ Selector.tag "a"
            , Selector.attribute (Html.Attributes.href href)
            , Selector.containing [ Selector.text linkText ]
            ]

        normalClick =
            ( "click"
            , Json.Encode.object
                [ ( "ctrlKey", Json.Encode.bool False )
                , ( "metaKey", Json.Encode.bool False )
                ]
            )

        ctrlClick =
            ( "click"
            , Json.Encode.object
                [ ( "ctrlKey", Json.Encode.bool True )
                , ( "metaKey", Json.Encode.bool False )
                ]
            )

        metaClick =
            ( "click"
            , Json.Encode.object
                [ ( "ctrlKey", Json.Encode.bool False )
                , ( "metaKey", Json.Encode.bool True )
                ]
            )

        tryClicking :
            { otherwise :
                Program model msg effect (SimulatedSub msg)
                -> TestState model msg effect
                -> Result Failure (TestState model msg effect)
            }
            -> ProgramTest model msg effect
            -> ProgramTest model msg effect
        tryClicking { otherwise } =
            andThen <|
                \program state ->
                    let
                        link =
                            Program.renderView program state.currentModel
                                |> Query.find findLinkTag
                    in
                    if respondsTo normalClick link then
                        -- there is a click handler
                        -- first make sure the handler properly respects "Open in new tab", etc
                        if respondsTo ctrlClick link || respondsTo metaClick link then
                            Err
                                (CustomFailure functionDescription
                                    (String.concat
                                        [ "Found an `<a href=\"...\">` tag has an onClick handler, "
                                        , "but the handler is overriding ctrl-click and meta-click.\n\n"
                                        , "A properly behaved single-page app should not override ctrl- and meta-clicks on `<a>` tags "
                                        , "because this prevents users from opening links in new tabs/windows.\n\n"
                                        , "Use `onClickPreventDefaultForLinkWithHref` defined at <https://gist.github.com/avh4/712d43d649b7624fab59285a70610707> instead of `onClick` to fix this problem.\n\n"
                                        , "See discussion of this issue at <https://github.com/elm-lang/navigation/issues/13>."
                                        ]
                                    )
                                )

                        else
                            -- everything looks good, so simulate that event and ignore the `href`
                            simulateHelper functionDescription (Query.find findLinkTag) normalClick program state

                    else
                        -- the link doesn't have a click handler
                        otherwise program state

        respondsTo event single =
            case
                single
                    |> Test.Html.Event.simulate event
                    |> Test.Html.Event.toResult
            of
                Err _ ->
                    False

                Ok _ ->
                    True
    in
    programTest
        |> assertComplexQuery functionDescription
            (ComplexQuery.find Nothing [ "a" ] findLinkTag)
        |> tryClicking { otherwise = \_ -> TestState.simulateLoadUrlHelper functionDescription href >> Err }


updateCookieJar : Dict String String -> ProgramTest model msg effect -> ProgramTest model msg effect
updateCookieJar newEntries =
    andThen <|
        \program state ->
            Ok { state | cookieJar = state.cookieJar |> Dict.union newEntries }


{-| Simulates replacing the text in an input field labeled with the given label.

1.  The id of the input field
    (which must match both the `id` attribute of the target `input` element,
    and the `for` attribute of the `label` element),
    or `""` if the `<input>` is a descendant of the `<label>`.

    NOTE: After [eeue56/elm-html-test#52](https://github.com/eeue56/elm-html-test/issues/52) is resolved,
    a future release of this package will remove this parameter.

2.  The label text of the input field.

3.  The text that will be entered into the input field.

There are a few different ways to accessibly label your input fields so that `fillIn` will find them:

  - You can place the `<input>` element inside a `<label>` element that also contains the label text.

    ```html
    <label>
        Favorite fruit
        <input>
    </label>
    ```

  - You can place the `<input>` and a `<label>` element anywhere on the page and link them with a unique id.

    ```html
    <label for="fruit">Favorite fruit</label>
    <input id="fruit"></input>
    ```

  - You can use the `aria-label` attribute.

    ```html
    <input aria-label="Favorite fruit"></input>
    ```

If you need to target a `<textarea>` that does not have a label,
see [`fillInTextarea`](#fillInTextArea).

If you need more control over finding the target element or creating the simulated event,
see [`simulateDomEvent`](#simulateDomEvent).

-}
fillIn : String -> String -> String -> ProgramTest model msg effect -> ProgramTest model msg effect
fillIn fieldId label newContent programTest =
    simulateLabeledInputHelper ("fillIn " ++ String.Extra.escape label)
        fieldId
        label
        True
        [-- TODO: should ensure that known special input types are not set, like `type="checkbox"`, etc?
        ]
        (Test.Html.Event.input newContent)
        programTest


fillInDom : String -> String -> String -> ProgramTest model msg effect -> ProgramTest model msg effect
fillInDom fieldId label newContent programTest =
    simulateLabeledInputHelper ("fillIn " ++ String.Extra.escape label)
        fieldId
        label
        True
        [-- TODO: should ensure that known special input types are not set, like `type="checkbox"`, etc?
        ]
        (Test.Html.Event.input newContent)
        (programTest
            |> (andThen <|
                    \_ state ->
                        Ok
                            (state
                                |> TestState.fillInField fieldId newContent
                            )
               )
        )


{-| Simulates replacing the text in a `<textarea>`.

This function expects that there is only one `<textarea>` in the view.
If your view has more than one `<textarea>`,
prefer adding associated `<label>` elements and use [`fillIn`](#fillIn).
If you cannot add `<label>` elements see [`within`](#within).

If you need more control over finding the target element or creating the simulated event,
see [`simulateDomEvent`](#simulateDomEvent).

-}
fillInTextarea : String -> ProgramTest model msg effect -> ProgramTest model msg effect
fillInTextarea newContent =
    simulateComplexQuery "fillInTextarea" <|
        (ComplexQuery.find Nothing [ "textarea" ] [ Selector.tag "textarea" ]
            >> ComplexQuery.simulate (Test.Html.Event.input newContent)
        )


{-| Simulates setting the value of a checkbox labeled with the given label.

The parameters are:

1.  The id of the input field
    (which must match both the `id` attribute of the target `input` element,
    and the `for` attribute of the `label` element),
    or `""` if the `<input>` is a descendant of the `<label>`.

    NOTE: After [eeue56/elm-html-test#52](https://github.com/eeue56/elm-html-test/issues/52) is resolved,
    a future release of this package will remove this parameter.

2.  The label text of the input field

3.  A `Bool` indicating whether to check (`True`) or uncheck (`False`) the checkbox.

NOTE: In the future, this will be generalized to work with
aria accessibility attributes in addition to working with standard HTML label elements.

If you need more control over finding the target element or creating the simulated event,
see [`simulateDomEvent`](#simulateDomEvent).

-}
check : String -> String -> Bool -> ProgramTest model msg effect -> ProgramTest model msg effect
check fieldId label willBecomeChecked programTest =
    simulateLabeledInputHelper ("check " ++ String.Extra.escape label)
        fieldId
        label
        False
        [ Selector.attribute (Html.Attributes.type_ "checkbox") ]
        (Test.Html.Event.check willBecomeChecked)
        programTest


{-| Simulates choosing an option with the given text in a select with a given label

The parameters are:

1.  The id of the `<select>`
    (which must match both the `id` attribute of the target `select` element,
    and the `for` attribute of the `label` element),
    or `""` if the `<select>` is a descendant of the `<label>`.

    NOTE: After [eeue56/elm-html-test#52](https://github.com/eeue56/elm-html-test/issues/52) is resolved,
    a future release of this package will remove this parameter.

2.  The label text of the select.

3.  The `value` of the `<option>` that will be chosen.

    NOTE: After [eeue56/elm-html-test#51](https://github.com/eeue56/elm-html-test/issues/51) is resolved,
    a future release of this package will remove this parameter.

4.  The user-visible text of the `<option>` that will be chosen.

Example: If you have a view like the following,

    import Html
    import Html.Attributes exposing (for, id, value)
    import Html.Events exposing (on, targetValue)

    Html.div []
        [ Html.label [ for "pet-select" ] [ Html.text "Choose a pet" ]
        , Html.select
            [ id "pet-select", on "change" targetValue ]
            [ Html.option [ value "dog" ] [ Html.text "Dog" ]
            , Html.option [ value "hamster" ] [ Html.text "Hamster" ]
            ]
        ]

you can simulate selecting an option like this:

    ProgramTest.selectOption "pet-select" "Choose a pet" "dog" "Dog"

If you need more control over finding the target element or creating the simulated event,
see [`simulateDomEvent`](#simulateDomEvent).

-}
selectOption : String -> String -> String -> String -> ProgramTest model msg effect -> ProgramTest model msg effect
selectOption fieldId label optionValue optionText =
    let
        functionDescription =
            String.join " "
                [ "selectOption"
                , String.Extra.escape fieldId
                , String.Extra.escape label
                , String.Extra.escape optionValue
                , String.Extra.escape optionText
                ]
    in
    simulateComplexQuery functionDescription <|
        ComplexQuery.check
            "check label exists"
            (ComplexQuery.find Nothing
                [ "label" ]
                [ Selector.tag "label"
                , Selector.attribute (Html.Attributes.for fieldId)
                , Selector.text label
                ]
            )
            >> (ComplexQuery.find (Just "find select")
                    [ "select" ]
                    [ Selector.tag "select"
                    , Selector.id fieldId
                    ]
                    >> ComplexQuery.check
                        "check option exists"
                        (ComplexQuery.find Nothing
                            [ "option" ]
                            [ Selector.tag "option"
                            , Selector.attribute (Html.Attributes.value optionValue)
                            , Selector.text optionText
                            ]
                        )
               )
            >> ComplexQuery.simulate
                ( "change"
                , Json.Encode.object
                    [ ( "target"
                      , Json.Encode.object
                            [ ( "value", Json.Encode.string optionValue )
                            ]
                      )
                    ]
                )


{-| Focus on a part of the view for a particular operation.

For example, if your view produces the following HTML:

```html
<div>
  <div id="sidebar">
    <button>Submit</button>
  </div>
  <div id="content">
    <button>Submit</button>
  </div>
</div>
```

then the following will allow you to simulate clicking the "Submit" button in the sidebar
(simply using `clickButton "Submit"` would fail because there are two buttons matching that text):

    import Test.Html.Query as Query
    import Test.Html.Selector exposing (id)

    programTest
        |> ProgramTest.within
            (Query.find [ id "sidebar" ])
            (ProgramTest.clickButton "Submit")
        |> ...

-}
within : (Query.Single msg -> Query.Single msg) -> (ProgramTest model msg effect -> ProgramTest model msg effect) -> (ProgramTest model msg effect -> ProgramTest model msg effect)
within findTarget onScopedTest =
    andThen (expectViewHelper "within" (findTarget >> Query.has []))
        >> (andThen <|
                \program state ->
                    case
                        Created
                            { state = Ok state
                            , program =
                                { program
                                    | withinFocus = program.withinFocus >> findTarget
                                }
                            }
                            |> onScopedTest
                    of
                        Created created ->
                            case created.state of
                                Ok s ->
                                    Ok s

                                Err e ->
                                    Err e.reason

                        FailedToCreate failure ->
                            Err failure
           )


{-| Asserts that an HTTP request to the specific url and method has been made.

The parameters are:

1.  The HTTP method of the expected request (typically `"GET"` or `"POST"`)
2.  The absolute URL of the expected request

For example:

    ...
        |> expectHttpRequestWasMade "GET" "https://example.com/api/data"

If you want to check the headers or request body, see [`expectHttpRequest`](#expectHttpRequest).
If you expect multiple requests to have been made to the same endpoint, see [`expectHttpRequests`](#expectHttpRequests).

NOTE: You must use [`withSimulatedEffects`](#withSimulatedEffects) before you call [`start`](#start) to be able to use this function.

If you want to interact with the program more after this assertion, see [`ensureHttpRequestWasMade`](#ensureHttpRequestWasMade).

-}
expectHttpRequestWasMade : String -> String -> ProgramTest model msg effect -> Expectation
expectHttpRequestWasMade method url programTest =
    programTest
        |> andThen (\_ -> expectHttpRequestHelper "expectHttpRequestWasMade" method url (checkSingleHttpRequest (always Expect.pass)))
        |> done


{-| See the documentation for [`expectHttpRequestWasMade`](#expectHttpRequestWasMade).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectHttpRequestWasMade` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureHttpRequestWasMade : String -> String -> ProgramTest model msg effect -> ProgramTest model msg effect
ensureHttpRequestWasMade method url =
    andThen (\_ -> expectHttpRequestHelper "ensureHttpRequestWasMade" method url (checkSingleHttpRequest (always Expect.pass)))


{-| Allows you to check the details of a pending HTTP request.

See the [“Expectations” section of `Test.Http`](Test-Http#expectations) for functions that might be helpful
in create an expectation on the request.

If you only care about whether the a request was made to the correct URL, see [`expectHttpRequestWasMade`](#expectHttpRequestWasMade).

    ...
        |> expectHttpRequest "POST"
            "https://example.com/save"
            (.body >> Expect.equal """{"content":"updated!"}""")

If you expect multiple requests to have been made to the same endpoint, see [`expectHttpRequests`](#expectHttpRequests).

NOTE: You must use [`withSimulatedEffects`](#withSimulatedEffects) before you call [`start`](#start) to be able to use this function.

If you want to interact with the program more after this assertion, see [`ensureHttpRequest`](#ensureHttpRequest).

-}
expectHttpRequest :
    String
    -> String
    -> (Test.Http.HttpRequest msg msg -> Expectation)
    -> ProgramTest model msg effect
    -> Expectation
expectHttpRequest method url checkRequest =
    andThen (\_ -> expectHttpRequestHelper "expectHttpRequest" method url (checkSingleHttpRequest checkRequest))
        >> done


{-| See the documentation for [`expectHttpRequest`](#expectHttpRequest).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectHttpRequest` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureHttpRequest :
    String
    -> String
    -> (Test.Http.HttpRequest msg msg -> Expectation)
    -> ProgramTest model msg effect
    -> ProgramTest model msg effect
ensureHttpRequest method url checkRequest =
    andThen (\_ -> expectHttpRequestHelper "ensureHttpRequest" method url (checkSingleHttpRequest checkRequest))


{-| Allows you to check the details of pending HTTP requests.

See the [“Expectations” section of `Test.Http`](Test-Http#expectations) for functions that might be helpful
in create an expectation on the request.

If your program will only have a single pending request to any particular URL, you can use the simpler [`expectHttpRequest`](#expectHttpRequest) (singular) or [`expectHttpRequestWasMade`](#expectHttpRequestWasMade) instead.

    ...
        |> expectHttpRequests "POST"
            "https://example.com/save"
            (List.map .body >> Expect.equal ["""body1""", """body2"""])

NOTE: You must use [`withSimulatedEffects`](#withSimulatedEffects) before you call [`start`](#start) to be able to use this function.

If you want to interact with the program more after this assertion, see [`ensureHttpRequests`](#ensureHttpRequests).

-}
expectHttpRequests :
    String
    -> String
    -> (List (Test.Http.HttpRequest msg msg) -> Expectation)
    -> ProgramTest model msg effect
    -> Expectation
expectHttpRequests method url checkRequests =
    andThen (\_ -> expectHttpRequestHelper "expectHttpRequests" method url (checkMultipleHttpRequests checkRequests))
        >> done


{-| See the documentation for [`expectHttpRequests`](#expectHttpRequests).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectHttpRequests` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureHttpRequests :
    String
    -> String
    -> (List (Test.Http.HttpRequest msg msg) -> Expectation)
    -> ProgramTest model msg effect
    -> ProgramTest model msg effect
ensureHttpRequests method url checkRequests =
    andThen (\_ -> expectHttpRequestHelper "ensureHttpRequests" method url (checkMultipleHttpRequests checkRequests))


checkSingleHttpRequest :
    (Test.Http.HttpRequest msg msg -> Expectation)
    -> List (Test.Http.HttpRequest msg msg)
    -> Result (String -> { method : String, url : String } -> List ( String, String ) -> Failure) ()
checkSingleHttpRequest checkRequest requests =
    case requests of
        [] ->
            Err (NoMatchingHttpRequest 1 0)

        [ request ] ->
            case Test.Runner.getFailureReason (checkRequest request) of
                Nothing ->
                    -- check succeeded
                    Ok ()

                Just reason ->
                    Err (\functionName _ _ -> ExpectFailed functionName reason.description reason.reason)

        (_ :: _ :: _) as many ->
            Err (MultipleMatchingHttpRequest 1 (List.length many))


checkMultipleHttpRequests :
    (List (Test.Http.HttpRequest msg msg) -> Expectation)
    -> List (Test.Http.HttpRequest msg msg)
    -> Result (String -> { method : String, url : String } -> List ( String, String ) -> Failure) ()
checkMultipleHttpRequests checkRequests requests =
    case Test.Runner.getFailureReason (checkRequests requests) of
        Nothing ->
            -- check succeeded
            Ok ()

        Just reason ->
            Err (\functionName _ _ -> ExpectFailed functionName reason.description reason.reason)


expectHttpRequestHelper :
    String
    -> String
    -> String
    -> (List (Test.Http.HttpRequest msg msg) -> Result (String -> { method : String, url : String } -> List ( String, String ) -> Failure) ())
    -> TestState model msg effect
    -> Result Failure (TestState model msg effect)
expectHttpRequestHelper functionName method url checkRequests state =
    case state.effectSimulation of
        Nothing ->
            Err (EffectSimulationNotConfigured functionName)

        Just simulation ->
            checkRequests (MultiDict.get ( method, url ) simulation.state.http)
                |> Result.map (\() -> state)
                |> Result.mapError (\f -> f functionName { method = method, url = url } (MultiDict.keys simulation.state.http))


{-| Simulates an HTTP 200 response to a pending request with the given method and url.

The parameters are:

1.  The HTTP method of the request to simulate a response for (typically `"GET"` or `"POST"`)
2.  The URL of the request to simulate a response for
3.  The response body for the simulated response

For example:

    ...
        |> simulateHttpOk "GET"
            "https://example.com/time.json"
            """{"currentTime":1559013158}"""
        |> ...

If you need to simulate an error, a response with a different status code,
or a response with response headers,
see [`simulateHttpResponse`](#simulateHttpResponse).

If you want to check the request headers or request body, use [`ensureHttpRequest`](#ensureHttpRequest)
immediately before using `simulateHttpOk`.

NOTE: You must use [`withSimulatedEffects`](#withSimulatedEffects) before you call [`start`](#start) to be able to use this function.

-}
simulateHttpOk : String -> String -> String -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateHttpOk method url responseBody =
    simulateHttpResponseHelper "simulateHttpOk"
        method
        url
        1
        True
        (Test.Http.httpResponse
            { statusCode = 200
            , body = responseBody
            , headers = []
            }
        )


{-| Simulates a response to a pending HTTP request.
The test will fail if there is no pending request matching the given method and url.

The parameters are:

1.  The HTTP method of the request to simulate a response for (typically `"GET"` or `"POST"`)
2.  The URL of the request to simulate a response for
3.  The [`Http.Response`](https://package.elm-lang.org/packages/elm/http/latest/Http#Response) value for the simulated response. You may find it helpful to see the [“Responses” section in `Test.Http`](Test-Http#responses)
    for convenient ways to create `Http.Response` values.

For example:

    ...
        |> simulateHttpResponse "GET"
            "https://example.com/time.json"
            Test.Http.networkError
        |> ...
        |> simulateHttpResponse "POST"
            "https://example.com/api/v1/process_data"
            (Test.Http.httpResponse
                { statusCode : 204
                , headers : [ ( "X-Procesing-Time", "1506ms") ]
                , body : ""
                }
            )

If you are simulating a 200 OK response and don't need to provide response headers,
you can use the simpler [`simulateHttpOk`](#simulateHttpOk).

If you want to check the request headers or request body, use [`ensureHttpRequest`](#ensureHttpRequest)
immediately before using `simulateHttpResponse`.

If your program will make multiple pending requests to the same URL, see [`simulateHttpResponseAdvanced`](#simulateHttpResponseAdvanced).

NOTE: You must use [`withSimulatedEffects`](#withSimulatedEffects) before you call [`start`](#start) to be able to use this function.

-}
simulateHttpResponse : String -> String -> Http.Response String -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateHttpResponse method url response =
    simulateHttpResponseHelper "simulateHttpResponse" method url 1 True response


{-| Simulates a response to one of several pending HTTP requests made to a given endpoint.

This is the same as [`simulateHttpResponse`](#simulateHttpResponse),
except that the additional `Int` parameter specificies which request to resolve if multiple requests to the same method/URL are pending.

-}
simulateHttpResponseAdvanced : String -> String -> Int -> Http.Response String -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateHttpResponseAdvanced method url pendingRequestIndex response =
    simulateHttpResponseHelper "simulateHttpResponseAdvanced" method url pendingRequestIndex False response


simulateHttpResponseHelper : String -> String -> String -> Int -> Bool -> Http.Response String -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateHttpResponseHelper functionName method url pendingRequestIndex failIfMorePendingRequests response =
    andThen <|
        \program state ->
            case state.effectSimulation of
                Nothing ->
                    Err (EffectSimulationNotConfigured functionName)

                Just simulation ->
                    case
                        MultiDict.get ( method, url ) simulation.state.http
                            |> List.Extra.splitAt (pendingRequestIndex - 1)
                    of
                        ( prev, [] ) ->
                            Err (NoMatchingHttpRequest pendingRequestIndex (List.length prev) functionName { method = method, url = url } (MultiDict.keys simulation.state.http))

                        ( prev, actualRequest :: rest ) ->
                            if failIfMorePendingRequests && rest /= [] then
                                Err (MultipleMatchingHttpRequest pendingRequestIndex (List.length prev + 1 + List.length rest) functionName { method = method, url = url } (MultiDict.keys simulation.state.http))

                            else
                                let
                                    resolveHttpRequest sim =
                                        let
                                            st =
                                                sim.state
                                        in
                                        { sim | state = { st | http = MultiDict.set ( method, url ) (prev ++ rest) st.http } }
                                in
                                state
                                    |> TestState.withSimulation
                                        (resolveHttpRequest
                                            >> EffectSimulation.queueTask (actualRequest.onRequestComplete response)
                                        )
                                    |> TestState.drain program


{-| Simulates the passing of time.
The `Int` parameter is the number of milliseconds to simulate.
This will cause any pending `Task.sleep`s to trigger if their delay has elapsed.

NOTE: You must use [`withSimulatedEffects`](#withSimulatedEffects) before you call [`start`](#start) to be able to use this function.

-}
advanceTime : Int -> ProgramTest model msg effect -> ProgramTest model msg effect
advanceTime delta =
    andThen (TestState.advanceTime "advanceTime" delta)


{-| Lets you assert on the values that the program being tested has sent to an outgoing port.

The parameters are:

1.  The name of the port
2.  A JSON decoder corresponding to the type of the port
3.  A function that will receive the list of values sent to the port
    since the start of the test (or since the last use of `ensureOutgoingPortValues`)
    and return an `Expectation`

For example:

    ...
        |> expectOutgoingPortValues
            "saveApiTokenToLocalStorage"
            Json.Decode.string
            (Expect.equal [ "975774a26612", "920facb1bac0" ])

For a more detailed explanation and example, see the [“Testing programs with ports” guidebook](https://elm-program-test.netlify.com/ports.html).

NOTE: You must use [`withSimulatedEffects`](#withSimulatedEffects) before you call [`start`](#start) to be able to use this function.

If you want to interact with the program more after this assertion, see [`ensureOutgoingPortValues`](#ensureOutgoingPortValues).

-}
expectOutgoingPortValues : String -> Json.Decode.Decoder a -> (List a -> Expectation) -> ProgramTest model msg effect -> Expectation
expectOutgoingPortValues portName decoder checkValues programTest =
    programTest
        |> expectOutgoingPortValuesHelper "expectOutgoingPortValues" portName decoder checkValues
        |> done


{-| See the documentation for [`expectOutgoingPortValues`](#expectOutgoingPortValues).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectOutgoingPortValues` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureOutgoingPortValues : String -> Json.Decode.Decoder a -> (List a -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
ensureOutgoingPortValues portName decoder checkValues programTest =
    expectOutgoingPortValuesHelper "ensureOutgoingPortValues" portName decoder checkValues programTest


expectOutgoingPortValuesHelper : String -> String -> Json.Decode.Decoder a -> (List a -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
expectOutgoingPortValuesHelper functionName portName decoder checkValues =
    andThen <|
        \_ state ->
            case state.effectSimulation of
                Nothing ->
                    Err (EffectSimulationNotConfigured functionName)

                Just simulation ->
                    case allOk <| List.map (Json.Decode.decodeValue decoder) <| EffectSimulation.outgoingPortValues portName simulation of
                        Err errs ->
                            Err (CustomFailure (functionName ++ ": failed to decode port values") (List.map Json.Decode.errorToString errs |> String.join "\n"))

                        Ok values ->
                            case Test.Runner.getFailureReason (checkValues values) of
                                Nothing ->
                                    -- the check passed
                                    Ok
                                        { state
                                            | effectSimulation =
                                                Just (EffectSimulation.clearOutgoingPortValues portName simulation)
                                        }

                                Just reason ->
                                    Err
                                        (ExpectFailed (functionName ++ ": values sent to port \"" ++ portName ++ "\" did not match")
                                            reason.description
                                            reason.reason
                                        )


allOk : List (Result x a) -> Result (List x) (List a)
allOk results =
    let
        step next acc =
            case ( next, acc ) of
                ( Ok n, Ok a ) ->
                    Ok (n :: a)

                ( Ok _, Err x ) ->
                    Err x

                ( Err n, Ok _ ) ->
                    Err [ n ]

                ( Err n, Err x ) ->
                    Err (n :: x)
    in
    List.foldl step (Ok []) results
        |> Result.map List.reverse
        |> Result.mapError List.reverse


{-| Lets you simulate a value being sent to the program being tested via an incoming port.

The parameters are:

1.  The name of the port
2.  The JSON representation of the incoming value

For example, here we are simulating the program receiving a list of strings on the incoming port
`port resultsFromJavascript : (List String -> msg) -> Sub msg`:

    ...
        |> ProgramTest.simulateIncomingPort
            "resultsFromJavascript"
            (Json.Encode.list Json.Encode.string
                [ "Garden-path sentences can confuse the reader." ]
            )

For a more detailed explanation and example, see the [“Testing programs with ports” guidebook](https://elm-program-test.netlify.com/ports.html).

NOTE: You must use [`withSimulatedSubscriptions`](#withSimulatedSubscriptions) before you call [`start`](#start) to be able to use this function.

-}
simulateIncomingPort : String -> Json.Encode.Value -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateIncomingPort portName value =
    let
        functionName =
            "simulateIncomingPort \"" ++ portName ++ "\""
    in
    andThen <|
        \program state ->
            case program.subscriptions of
                Nothing ->
                    Err (CustomFailure functionName "you MUST use ProgramTest.withSimulatedSubscriptions to be able to use simulateIncomingPort")

                Just fn ->
                    let
                        matches =
                            matchesFromSub (fn state.currentModel)

                        matchesFromSub : SimulatedSub msg -> List (Result String msg)
                        matchesFromSub sub =
                            case sub of
                                SimulatedEffect.NoneSub ->
                                    []

                                SimulatedEffect.BatchSub subs_ ->
                                    List.concatMap matchesFromSub subs_

                                SimulatedEffect.PortSub pname decoder ->
                                    if pname == portName then
                                        Json.Decode.decodeValue decoder value
                                            |> Result.mapError Json.Decode.errorToString
                                            |> List.singleton

                                    else
                                        []

                        step : Result String msg -> TestState model msg effect -> Result Failure (TestState model msg effect)
                        step r tc =
                            case r of
                                Err message ->
                                    Err
                                        (CustomFailure functionName
                                            ("the value provided does not match the type that the port is expecting:\n"
                                                ++ message
                                            )
                                        )

                                Ok msg ->
                                    TestState.update msg program tc
                    in
                    if matches == [] then
                        Err (CustomFailure functionName "the program is not currently subscribed to the port")

                    else
                        List.foldl (\match -> Result.andThen (step match)) (Ok state) matches


{-| Simulates a route change event (which would happen when your program is
a `Browser.application` and the user manually changes the URL in the browser's URL bar).

The parameter may be an absolute URL or relative URL.

-}
routeChange : String -> ProgramTest model msg effect -> ProgramTest model msg effect
routeChange url =
    andThen (TestState.routeChangeHelper "routeChange" 0 url)


{-| Make an assertion about the current state of a `ProgramTest`'s model.

When possible, you should prefer making assertions about the rendered view (see [`expectView`](#expectView))
or external requests made by your program (see [`expectHttpRequest`](#expectHttpRequest), [`expectOutgoingPortValues`](#expectOutgoingPortValues)),
as testing at the level that users and external services interact with your program
will make your tests more resilient to changes in the private implementation of your program.

-}
expectModel : (model -> Expectation) -> ProgramTest model msg effect -> Expectation
expectModel assertion =
    (andThen <|
        \_ state ->
            case assertion state.currentModel |> Test.Runner.getFailureReason of
                Nothing ->
                    Ok state

                Just reason ->
                    Err (ExpectFailed "expectModel" reason.description reason.reason)
    )
        >> done


{-| Simulate the outcome of the last effect produced by the program being tested
by providing a function that can convert the last effect into `msg`s.

The function you provide will be called with the effect that was returned by the most recent call to `update` or `init` in the `ProgramTest`.

  - If it returns `Err`, then the `ProgramTest` will enter a failure state with the provided error message.
  - If it returns `Ok`, then the list of `msg`s will be applied in order via `ProgramTest.update`.

NOTE: If you are simulating HTTP responses,
you should prefer more specific functions designed for that purpose.
You can find links to the relevant documentation in the [documentation index](#documentation-index).

-}
simulateLastEffect : (effect -> Result String (List msg)) -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateLastEffect toMsgs =
    andThen <|
        \program state ->
            case toMsgs state.lastEffect of
                Ok msgs ->
                    List.foldl (\msg -> Result.andThen (TestState.update msg program)) (Ok state) msgs

                Err message ->
                    Err (SimulateLastEffectFailed message)


expectLastEffectHelper : String -> (effect -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
expectLastEffectHelper functionName assertion =
    andThen <|
        \_ state ->
            case assertion state.lastEffect |> Test.Runner.getFailureReason of
                Nothing ->
                    Ok state

                Just reason ->
                    Err (ExpectFailed functionName reason.description reason.reason)


{-| See the documentation for [`expectLastEffect`](#expectLastEffect).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectLastEffect` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureLastEffect : (effect -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
ensureLastEffect assertion programTest =
    expectLastEffectHelper "ensureLastEffect" assertion programTest


{-| Makes an assertion about the last effect produced by a `ProgramTest`'s program.

NOTE: If you are asserting about HTTP requests or outgoing ports,
you should prefer more specific functions designed for that purpose.
You can find links to the relevant documentation in the [documentation index](#documentation-index).

If you want to interact with the program more after this assertion, see [`ensureLastEffect`](#ensureLastEffect).

-}
expectLastEffect : (effect -> Expectation) -> ProgramTest model msg effect -> Expectation
expectLastEffect assertion programTest =
    programTest
        |> expectLastEffectHelper "expectLastEffect" assertion
        |> done


expectViewHelper :
    String
    -> (Query.Single msg -> Expectation)
    -> Program model msg effect sub
    -> TestState model msg effect
    -> Result Failure (TestState model msg effect)
expectViewHelper functionName assertion program state =
    case
        Program.renderView program state.currentModel
            |> assertion
            |> Test.Runner.getFailureReason
    of
        Nothing ->
            Ok state

        Just reason ->
            Err (ExpectFailed functionName reason.description reason.reason)


{-| See the documentation for [`expectView`](#expectView).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectView` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureView : (Query.Single msg -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
ensureView assertion =
    andThen (expectViewHelper "ensureView" assertion)


{-| See the documentation for [`expectViewHas`](#expectViewHas).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectViewHas` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureViewHas : List Selector.Selector -> ProgramTest model msg effect -> ProgramTest model msg effect
ensureViewHas selector =
    andThen (expectViewHelper "ensureViewHas" (Query.has selector))


{-| See the documentation for [`expectViewHasNot`](#expectViewHasNot).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectViewHasNot` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureViewHasNot : List Selector.Selector -> ProgramTest model msg effect -> ProgramTest model msg effect
ensureViewHasNot selector =
    andThen (expectViewHelper "ensureViewHasNot" (Query.hasNot selector))


{-| Makes an assertion about the current state of a `ProgramTest`'s view.

If you want to interact with the program more after this assertion, see [`ensureView`](#ensureView).

-}
expectView : (Query.Single msg -> Expectation) -> ProgramTest model msg effect -> Expectation
expectView assertion =
    andThen (expectViewHelper "expectView" assertion)
        >> done


{-| A simpler way to assert that a `ProgramTest`'s view matches a given selector.

`expectViewHas [...selector...]` is the same as `expectView (Test.Html.Query.has [...selector...])`.

If you want to interact with the program more after this assertion, see [`ensureViewHas`](#ensureViewHas).

-}
expectViewHas : List Selector.Selector -> ProgramTest model msg effect -> Expectation
expectViewHas selector =
    andThen (expectViewHelper "expectViewHas" (Query.has selector))
        >> done


{-| A simpler way to assert that a `ProgramTest`'s view does not match a given selector.

`expectViewHasNot [...selector...]` is the same as `expectView (Test.Html.Query.hasNot [...selector...])`.

If you want to interact with the program more after this assertion, see [`ensureViewHasNot`](#ensureViewHasNot).

-}
expectViewHasNot : List Selector.Selector -> ProgramTest model msg effect -> Expectation
expectViewHasNot selector =
    andThen (expectViewHelper "expectViewHasNot" (Query.hasNot selector))
        >> done


{-| Ends a `ProgramTest`, reporting any errors that occurred.

You can also end a `ProgramTest` using any of the functions starting with `expect*`.
In fact, you should prefer using one of the `expect*` functions when possible,
as doing so will [make the intent of your test more clear](https://www.artima.com/weblogs/viewpost.jsp?thread=35578).

-}
done : ProgramTest model msg effect -> Expectation
done programTest =
    case toFailure programTest of
        Nothing ->
            Expect.pass

        Just failure ->
            Expect.fail (Failure.toString failure)


{-| Asserts that the program ended by navigating away to another URL.

The parameter is:

1.  The expected URL that the program should have navigated away to.

If your program is an application that manages URL changes
(created with [`createApplication`](#createApplication)),
then you probably want [`expectBrowserUrl`](#expectBrowserUrl) instead.

-}
expectPageChange : String -> ProgramTest model msg effect -> Expectation
expectPageChange expectedUrl programTest =
    case toFailure programTest of
        Just (ChangedPage cause finalLocation) ->
            Url.toString finalLocation |> Expect.equal expectedUrl

        Just _ ->
            programTest |> done

        Nothing ->
            Expect.fail "expectPageChange: expected to have navigated to a different URL, but no links were clicked and no browser navigation was simulated"


{-| Asserts on the current value of the browser URL bar in the simulated test environment.

The parameter is:

1.  A function that asserts on the current URL. Typically you will use `Expect.equal` with the exact URL you expect.

If your program is _not_ an application that manages URL changes
and you want to assert that the user clicked a link that goes to an external web page,
then you probably want [`expectPageChange`](#expectPageChange) instead.

-}
expectBrowserUrl : (String -> Expectation) -> ProgramTest model msg effect -> Expectation
expectBrowserUrl checkUrl programTest =
    expectBrowserUrlHelper "expectBrowserUrl" checkUrl programTest
        |> done


{-| See the documentation for [`expectBrowserUrl`](#expectBrowserUrl).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectBrowserUrl` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureBrowserUrl : (String -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
ensureBrowserUrl checkUrl programTest =
    expectBrowserUrlHelper "ensureBrowserUrl" checkUrl programTest


expectBrowserUrlHelper : String -> (String -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
expectBrowserUrlHelper functionName checkUrl =
    andThen <|
        \_ state ->
            case Maybe.map .currentLocation state.navigation of
                Nothing ->
                    Err (ProgramDoesNotSupportNavigation functionName)

                Just url ->
                    case Test.Runner.getFailureReason (checkUrl (Url.toString url)) of
                        Nothing ->
                            -- check succeeded
                            Ok state

                        Just reason ->
                            Err (ExpectFailed functionName reason.description reason.reason)


{-| Asserts on the current browser history in the simulated test environment.
This only makes sense if you are using [`withSimulatedEffects`](#withSimulatedEffects)
and the function you provide to it produces
[`SimulatedEffect.Navigation.replaceUrl`](SimulatedEffect-Navigation#replaceUrl) or
[`SimulatedEffect.Navigation.pushUrl`](SimulatedEffect-Navigation#pushUrl)
for one or more of your effects.
The previous URL is added to the simulated browser history whenever a `pushUrl` effect is simulated.

The parameter is:

1.  A function that asserts on the current browser history (most recent at the head) to an expectation.

Example: If there's only one expected item in the history or if you want check the complete history since the start of the test, use this with `Expect.equal`

    createApplication { ... }
        |> withBaseUrl "https://example.com/resource/123"
        |> start ()
        |> clickButton "Details"
        |> expectBrowserHistory (Expect.equal [ "https://example.com/resource/123/details" ])

Example: If there might be multiple items in the history and you only want to check the most recent item:

    createApplication { ... }
        |> withBaseUrl "https://example.com/resource/123"
        |> start ()
        |> clickButton "Details"
        |> clickButton "Calendar"
        |> expectBrowserHistory (List.head >> Expect.equal (Just "https://example.com/resource/123/calendar"))

If you need to assert on the current URL, see [`expectBrowserUrl`](#expectBrowserUrl).

-}
expectBrowserHistory : (List String -> Expectation) -> ProgramTest model msg effect -> Expectation
expectBrowserHistory checkHistory programTest =
    expectBrowserHistoryHelper "expectBrowserHistory" checkHistory programTest
        |> done


{-| See the documentation for [`expectBrowserHistory`](#expectBrowserHistory).
This is the same except that it returns a `ProgramTest` instead of an `Expectation`
so that you can interact with the program further after this assertion.

You should prefer `expectBrowserHistory` when possible,
as having a single assertion per test can make the intent of your tests more clear.

-}
ensureBrowserHistory : (List String -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
ensureBrowserHistory checkHistory programTest =
    expectBrowserHistoryHelper "ensureBrowserHistory" checkHistory programTest


expectBrowserHistoryHelper : String -> (List String -> Expectation) -> ProgramTest model msg effect -> ProgramTest model msg effect
expectBrowserHistoryHelper functionName checkHistory =
    andThen <|
        \_ state ->
            case Maybe.map .browserHistory state.navigation of
                Nothing ->
                    -- TODO: use withBaseUrl error
                    Err (ProgramDoesNotSupportNavigation functionName)

                Just browserHistoryYes ->
                    case Test.Runner.getFailureReason (checkHistory (List.map Url.toString browserHistoryYes)) of
                        Nothing ->
                            -- check succeeded
                            Ok state

                        Just reason ->
                            Err (ExpectFailed functionName reason.description reason.reason)


{-| `fail` can be used to report custom errors if you are writing your own convenience functions to deal with program tests.

For example, this function checks for a particular structure in the program's view,
but will also fail the ProgramTest if the `expectedCount` parameter is invalid:

    expectNotificationCount : Int -> ProgramTest model msg effect -> Expectation
    expectNotificationCount expectedCount programTest =
        if expectedCount <= 0 then
            programTest
                |> ProgramTest.fail "expectNotificationCount"
                    ("expectedCount must be positive, but was: " ++ String.fromInt expectedCount)

        else
            programTest
                |> expectViewHas
                    [ Test.Html.Selector.class "notifications"
                    , Test.Html.Selector.text (toString expectedCount)
                    ]

If you are writing a convenience function that is creating a program test, see [`createFailed`](#createFailed).

-}
fail : String -> String -> ProgramTest model msg effect -> ProgramTest model msg effect
fail assertionName failureMessage =
    andThen <| \_ _ -> Err (CustomFailure assertionName failureMessage)


{-| `createFailed` can be used to report custom errors if you are writing your own convenience functions to _create_ program tests.

NOTE: if you are writing a convenience function that takes a `ProgramTest` as input, you should use [`fail`](#fail) instead,
as it provides more context in the test failure message.

The parameters are:

1.  The name of your helper function (displayed in failure messages)
2.  The failure message (also included in the failure message)

For example:

    -- JsonSchema and MyProgram are imaginary modules for this example


    import JsonSchema exposing (Schema, validateJsonSchema)
    import MyProgram exposing (Model, Msg)
    import ProgramTest exposing (ProgramTest)

    createWithValidatedJson : Schema -> String -> ProgramTest Model Msg (Cmd Msg)
    createWithValidatedJson schema json =
        case validateJsonSchema schema json of
            Err message ->
                ProgramTest.createFailed
                    "createWithValidatedJson"
                    ("JSON schema validation failed:\n" ++ message)

            Ok () ->
                ProgramTest.createElement
                    { init = MyProgram.init
                    , update = MyProgram.update
                    , view = MyProgram.view
                    }
                    |> ProgramTest.start json

-}
createFailed : String -> String -> ProgramTest model msg effect
createFailed functionName failureMessage =
    FailedToCreate (CustomFailure functionName failureMessage)


{-| This can be used for advanced helper functions where you want to continue a test but need the data
sent out through ports later in your test.

NOTE: If you do not need this advanced functionality,
prefer [`expectOutgoingPortValues`](#expectOutgoingPortValues) instead.

-}
getOutgoingPortValues : String -> ProgramTest model msg effect -> Result (ProgramTest model msg effect) (List Json.Encode.Value)
getOutgoingPortValues portName programTest =
    case programTest of
        FailedToCreate _ ->
            Err programTest

        Created ({ program, state } as created) ->
            case state of
                Err _ ->
                    Err programTest

                Ok s ->
                    case s.effectSimulation of
                        Nothing ->
                            Err <|
                                Created
                                    { created
                                        | state =
                                            TestResult.fail (EffectSimulationNotConfigured "getPortValues") s
                                    }

                        Just effects ->
                            Dict.get portName effects.outgoingPortValues
                                |> Maybe.withDefault []
                                |> Ok
