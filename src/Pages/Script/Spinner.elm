module Pages.Script.Spinner exposing (CompletionIcon(..), Options, Spinner, Steps(..), options, runSteps, runTask, runTaskExisting, runTaskWithOptions, showStep, spinner, start, steps, withImmediateStart, withNamedAnimation, withOnCompletion, withStep, withStepWithOptions)

{-|

@docs CompletionIcon, Options, Spinner, Steps, options, runSteps, runTask, runTaskExisting, runTaskWithOptions, showStep, spinner, start, steps, withImmediateStart, withNamedAnimation, withOnCompletion, withStep, withStepWithOptions

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode


{-| -}
type CompletionIcon
    = Succeed
    | Fail
    | Warn
    | Info
    | Custom String


{-| -}
type Options error value
    = Options
        { text : String
        , animation : Maybe String
        , immediateStart : Bool
        , onCompletion : Result error value -> ( CompletionIcon, Maybe String )
        }


{-| -}
withOnCompletion : (Result error value -> ( CompletionIcon, Maybe String )) -> Options error value -> Options error value
withOnCompletion function (Options options_) =
    Options { options_ | onCompletion = function }


{-| -}
type Spinner error value
    = Spinner String (Options error value)


{-| -}
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


{-| -}
withNamedAnimation : String -> Options error value -> Options error value
withNamedAnimation animationName (Options options_) =
    Options { options_ | animation = Just animationName }


{-| A low-level helper for showing a step and getting back a `Spinner` reference which you can later use to `start` the spinner.
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


{-| -}
withImmediateStart : Options error value -> Options error value
withImmediateStart (Options options_) =
    Options { options_ | immediateStart = True }


{-| -}
runTaskWithOptions : Options error value -> BackendTask error value -> BackendTask error value
runTaskWithOptions (Options options_) backendTask =
    Options options_
        |> withImmediateStart
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
                    ( Fail, Just "Uh oh! Failed to fetch" )
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
                    , ( "immediateStart", Encode.bool True )
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

        Custom _ ->
            "custom"


{-| -}
type Steps error value
    = Steps (BackendTask error value)


{-| -}
steps : Steps FatalError ()
steps =
    Steps (BackendTask.succeed ())


{-| -}
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


{-| -}
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


{-| -}
runSteps : Steps FatalError value -> BackendTask FatalError value
runSteps (Steps steps_) =
    steps_
