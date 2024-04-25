module Pages.Script.Spinner exposing
    ( Steps(..), steps, withStep
    , withStepWithOptions
    , runSteps
    , Options, options
    , CompletionIcon(..)
    , withOnCompletion
    , runTask, runTaskWithOptions
    , showStep, runTaskExisting, start, Spinner
    )

{-|


## Running Steps

The easiest way to use spinners is to define a series of [`Steps`](#Steps) and then run them with [`runSteps`](#runSteps).

Steps are a sequential series of `BackendTask`s that are run one after the other. If a step fails (has a [`FatalError`](FatalError)),
its spinner will show a failure, and the remaining steps will not be run and will be displayed as cancelled (the step name in gray).

    module StepsDemo exposing (run)

    import BackendTask exposing (BackendTask)
    import Pages.Script as Script exposing (Script)
    import Pages.Script.Spinner as Spinner

    run : Script
    run =
        Script.withoutCliOptions
            (Spinner.steps
                |> Spinner.withStep "Compile Main.elm" (\() -> Script.exec "elm" [ "make", "src/Main.elm", "--output=/dev/null" ])
                |> Spinner.withStep "Verify formatting" (\() -> Script.exec "elm-format" [ "--validate", "src/" ])
                |> Spinner.withStep "elm-review" (\() -> Script.exec "elm-review" [])
                |> Spinner.runSteps
            )

@docs Steps, steps, withStep

@docs withStepWithOptions

@docs runSteps


## Configuring Steps

@docs Options, options

@docs CompletionIcon

@docs withOnCompletion


## Running with BackendTask

@docs runTask, runTaskWithOptions


## Low-Level

@docs showStep, runTaskExisting, start, Spinner

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode


{-| An icon used to indicate the completion status of a step. Set by using [`withOnCompletion`](#withOnCompletion).
-}
type CompletionIcon
    = Succeed
    | Fail
    | Warn
    | Info


{-| Configuration that can be used with [`runTaskWithOptions`](#runTaskWithOptions) and [`withStepWithOptions`](#withStepWithOptions).
-}
type Options error value
    = Options
        { text : String
        , animation : Maybe String
        , immediateStart : Bool
        , onCompletion : Result error value -> ( CompletionIcon, Maybe String )
        }


{-| Set the completion icon and text based on the result of the task.

    import Pages.Script.Spinner as Spinner

    example =
        Spinner.options "Fetching data"
            |> Spinner.withOnCompletion
                (\result ->
                    case result of
                        Ok _ ->
                            ( Spinner.Succeed, "Fetched data!" )

                        Err _ ->
                            ( Spinner.Fail
                            , Just "Could not fetch data."
                            )
                )

-}
withOnCompletion : (Result error value -> ( CompletionIcon, Maybe String )) -> Options error value -> Options error value
withOnCompletion function (Options options_) =
    Options { options_ | onCompletion = function }


{-| -}
type Spinner error value
    = Spinner String (Options error value)


{-| The default options for a spinner. The spinner `text` is a required argument and will be displayed as the step name.

    import Pages.Script.Spinner as Spinner

    example =
        Spinner.options "Compile Main.elm"

-}
options : String -> Options error value
options text =
    Options
        { text = text
        , animation = Nothing
        , immediateStart = False
        , onCompletion =
            \result ->
                case result of
                    Ok _ ->
                        ( Succeed, Nothing )

                    Err _ ->
                        ( Fail, Nothing )
        }



--{-| -}
--withNamedAnimation : String -> Options error value -> Options error value
--withNamedAnimation animationName (Options options_) =
--    Options { options_ | animation = Just animationName }


{-| `showStep` gives you a `Spinner` reference which you can use to start the spinner later with `start`.

Most use cases can be achieved more easily using more high-level helpers, like [`runTask`](#runTask) or [`steps`](#steps).
`showStep` can be useful if you have more dynamic steps that you want to reveal over time.

    module ShowStepDemo exposing (run)

    import BackendTask exposing (BackendTask)
    import Pages.Script as Script exposing (Script, doThen, sleep)
    import Pages.Script.Spinner as Spinner

    run : Script
    run =
        Script.withoutCliOptions
            (BackendTask.succeed
                (\spinner1 spinner2 spinner3 ->
                    sleep 3000
                        |> Spinner.runTaskExisting spinner1
                        |> doThen
                            (sleep 3000
                                |> Spinner.runTaskExisting spinner2
                                |> doThen
                                    (sleep 3000
                                        |> Spinner.runTaskExisting spinner3
                                    )
                            )
                )
                |> BackendTask.andMap
                    (Spinner.options "Step 1" |> Spinner.showStep)
                |> BackendTask.andMap
                    (Spinner.options "Step 2" |> Spinner.showStep)
                |> BackendTask.andMap
                    (Spinner.options "Step 3" |> Spinner.showStep)
                |> BackendTask.andThen identity
            )

-}
showStep : Options error value -> BackendTask error (Spinner error value)
showStep (Options options_) =
    BackendTask.Internal.Request.request
        { name = "start-spinner"
        , body =
            BackendTask.Http.jsonBody
                ([ ( "text", Encode.string options_.text ) |> Just
                 , ( "immediateStart", Encode.bool options_.immediateStart ) |> Just
                 , options_.animation |> Maybe.map (\animation -> ( "spinner", Encode.string animation ))
                 ]
                    |> List.filterMap identity
                    |> Encode.object
                )
        , expect =
            BackendTask.Http.expectJson
                (Decode.map
                    (\s -> Spinner s (Options options_))
                    Decode.string
                )
        }


{-| -}
start : Spinner error1 value1 -> BackendTask error ()
start (Spinner spinnerId _) =
    BackendTask.Internal.Request.request
        { name = "start-spinner"
        , body =
            BackendTask.Http.jsonBody
                ([ ( "spinnerId", Encode.string spinnerId )
                 ]
                    |> Encode.object
                )
        , expect =
            BackendTask.Http.expectJson (Decode.succeed ())
        }



--{-| -}
--withImmediateStart : Options error value -> Options error value
--withImmediateStart (Options options_) =
--    Options { options_ | immediateStart = True }


{-| -}
runTaskWithOptions : Options error value -> BackendTask error value -> BackendTask error value
runTaskWithOptions (Options options_) backendTask =
    Options options_
        --|> withImmediateStart
        |> showStep
        |> BackendTask.andThen
            (\(Spinner spinnerId _) ->
                backendTask
                    |> BackendTask.onError
                        (\error ->
                            let
                                ( completionIcon, completionText ) =
                                    options_.onCompletion (Err error)
                            in
                            BackendTask.Internal.Request.request
                                { name = "stop-spinner"
                                , body =
                                    BackendTask.Http.jsonBody
                                        (Encode.object
                                            [ ( "spinnerId", Encode.string spinnerId )
                                            , ( "completionFn", encodeCompletionIcon completionIcon |> Encode.string )
                                            , ( "completionText", completionText |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
                                            ]
                                        )
                                , expect = BackendTask.Http.expectJson (Decode.succeed ())
                                }
                                |> BackendTask.andThen (\() -> BackendTask.fail error)
                        )
                    |> BackendTask.andThen
                        (\value ->
                            let
                                ( completionIcon, completionText ) =
                                    options_.onCompletion (Ok value)
                            in
                            BackendTask.Internal.Request.request
                                { name = "stop-spinner"
                                , body =
                                    BackendTask.Http.jsonBody
                                        (Encode.object
                                            [ ( "spinnerId", Encode.string spinnerId )
                                            , ( "completionFn", encodeCompletionIcon completionIcon |> Encode.string )
                                            , ( "completionText", completionText |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
                                            ]
                                        )
                                , expect = BackendTask.Http.expectJson (Decode.succeed value)
                                }
                        )
            )


{-| -}
runTask : String -> BackendTask error value -> BackendTask error value
runTask text backendTask =
    spinner text
        (\result ->
            case result of
                Ok _ ->
                    ( Succeed, Nothing )

                Err _ ->
                    ( Fail, Nothing )
        )
        backendTask


{-| -}
runTaskExisting : Spinner error value -> BackendTask error value -> BackendTask error value
runTaskExisting (Spinner spinnerId (Options options_)) backendTask =
    BackendTask.Internal.Request.request
        { name = "start-spinner"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "text", Encode.string options_.text )
                    , ( "spinnerId", Encode.string spinnerId )
                    , ( "immediateStart", Encode.bool options_.immediateStart )
                    , ( "spinner", Encode.string "line" )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }
        |> BackendTask.andThen (\() -> backendTask)
        |> BackendTask.andThen
            (\value ->
                let
                    ( completionIcon, completionText ) =
                        options_.onCompletion (Ok value)
                in
                BackendTask.Internal.Request.request
                    { name = "stop-spinner"
                    , body =
                        BackendTask.Http.jsonBody
                            (Encode.object
                                [ ( "spinnerId", Encode.string spinnerId )
                                , ( "completionFn", encodeCompletionIcon completionIcon |> Encode.string )
                                , ( "completionText", completionText |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
                                ]
                            )
                    , expect = BackendTask.Http.expectJson (Decode.succeed value)
                    }
            )
        |> BackendTask.onError
            (\error ->
                let
                    ( completionIcon, completionText ) =
                        options_.onCompletion (Err error)
                in
                BackendTask.Internal.Request.request
                    { name = "stop-spinner"
                    , body =
                        BackendTask.Http.jsonBody
                            (Encode.object
                                [ ( "spinnerId", Encode.string spinnerId )
                                , ( "completionFn", encodeCompletionIcon completionIcon |> Encode.string )
                                , ( "completionText", completionText |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
                                ]
                            )
                    , expect = BackendTask.Http.expectJson (Decode.succeed ())
                    }
                    |> BackendTask.andThen (\() -> BackendTask.fail error)
            )


{-| -}
spinner : String -> (Result error value -> ( CompletionIcon, Maybe String )) -> BackendTask error value -> BackendTask error value
spinner text onCompletion task =
    BackendTask.Internal.Request.request
        { name = "start-spinner"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "text", Encode.string text )
                    , ( "immediateStart", Encode.bool True )
                    , ( "spinner", Encode.string "line" )

                    -- TODO more ora options here
                    ]
                )
        , expect =
            BackendTask.Http.expectJson Decode.string
        }
        |> BackendTask.andThen
            (\spinnerId ->
                task
                    |> BackendTask.onError
                        (\error ->
                            let
                                ( completionIcon, completionText ) =
                                    onCompletion (Err error)
                            in
                            BackendTask.Internal.Request.request
                                { name = "stop-spinner"
                                , body =
                                    BackendTask.Http.jsonBody
                                        (Encode.object
                                            [ ( "spinnerId", Encode.string spinnerId )
                                            , ( "completionFn", encodeCompletionIcon completionIcon |> Encode.string )
                                            , ( "completionText", completionText |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
                                            ]
                                        )
                                , expect = BackendTask.Http.expectJson (Decode.succeed ())
                                }
                                |> BackendTask.andThen (\() -> BackendTask.fail error)
                        )
                    |> BackendTask.andThen
                        (\value ->
                            let
                                ( completionIcon, completionText ) =
                                    onCompletion (Ok value)
                            in
                            BackendTask.Internal.Request.request
                                { name = "stop-spinner"
                                , body =
                                    BackendTask.Http.jsonBody
                                        (Encode.object
                                            [ ( "spinnerId", Encode.string spinnerId )
                                            , ( "completionFn", encodeCompletionIcon completionIcon |> Encode.string )
                                            , ( "completionText", completionText |> Maybe.map Encode.string |> Maybe.withDefault Encode.null )
                                            ]
                                        )
                                , expect = BackendTask.Http.expectJson (Decode.succeed value)
                                }
                        )
            )


encodeCompletionIcon : CompletionIcon -> String
encodeCompletionIcon completionIcon =
    case completionIcon of
        Succeed ->
            "succeed"

        Fail ->
            "fail"

        Warn ->
            "warn"

        Info ->
            "info"


{-| The definition of a series of `BackendTask`s to run, with a spinner for each step.
-}
type Steps error value
    = Steps (BackendTask error value)


{-| Initialize an empty series of `Steps`.
-}
steps : Steps FatalError ()
steps =
    Steps (BackendTask.succeed ())


{-| Add a `Step`. See [`withStepWithOptions`](#withStepWithOptions) to configure the step's spinner.
-}
withStep : String -> (oldValue -> BackendTask FatalError newValue) -> Steps FatalError oldValue -> Steps FatalError newValue
withStep text backendTask steps_ =
    case steps_ of
        Steps previousSteps ->
            Steps
                (BackendTask.map2
                    (\pipelineValue newSpinner ->
                        runTaskExisting
                            newSpinner
                            (backendTask pipelineValue)
                    )
                    previousSteps
                    (options text |> showStep)
                    |> BackendTask.andThen identity
                )


{-| Add a step with custom [`Options`](#Options).
-}
withStepWithOptions : Options FatalError newValue -> (oldValue -> BackendTask FatalError newValue) -> Steps FatalError oldValue -> Steps FatalError newValue
withStepWithOptions options_ backendTask steps_ =
    case steps_ of
        Steps previousSteps ->
            Steps
                (BackendTask.map2
                    (\pipelineValue newSpinner ->
                        runTaskExisting
                            newSpinner
                            (backendTask pipelineValue)
                    )
                    previousSteps
                    (showStep options_)
                    |> BackendTask.andThen identity
                )


{-| Perform the `Steps` in sequence.
-}
runSteps : Steps FatalError value -> BackendTask FatalError value
runSteps (Steps steps_) =
    steps_
