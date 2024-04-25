module Pages.Internal.Platform.GeneratorApplication exposing (Program, Flags, Model, Msg(..), init, requestDecoder, update, app, JsonValue)

{-| Exposed for internal use only (used in generated code).

@docs Program, Flags, Model, Msg, init, requestDecoder, update, app, JsonValue

-}

import BackendTask exposing (BackendTask)
import BuildError exposing (BuildError)
import Cli.Program as Program exposing (FlagsIncludingArgv)
import Codec
import Dict
import FatalError exposing (FatalError)
import HtmlPrinter
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.GeneratorProgramConfig exposing (GeneratorProgramConfig)
import Pages.Internal.Platform.CompatibilityKey
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.StaticResponses as StaticResponses
import Pages.Internal.Platform.ToJsPayload as ToJsPayload
import Pages.Internal.Script
import Pages.StaticHttp.Request
import TerminalText as Terminal


{-| -}
type alias JsonValue =
    Decode.Value


{-| -}
type alias Program model msg =
    Program.StatefulProgram (Model model msg) (Msg msg) (BackendTask FatalError ()) Flags


{-| -}
type alias Flags =
    { compatibilityKey : Int
    }


{-| -}
type alias Model model msg =
    { staticResponses : BackendTask FatalError ()
    , errors : List BuildError
    , model : model
    , subscriptions : model -> Sub msg
    }


{-| -}
type Msg msg
    = GotDataBatch Decode.Value
    | GotBuildError BuildError
    | Msg msg


{-| -}
app :
    GeneratorProgramConfig model msg
    -> Program model msg
app config =
    let
        cliConfig :
            { perform : BackendTask Never msg -> Cmd msg }
            ->
                Program.Config
                    { init : BackendTask FatalError ( model, Cmd msg )
                    , subscriptions : model -> Sub msg
                    , update : msg -> model -> ( model, Cmd msg )
                    }
        cliConfig performRecord =
            case config.data of
                Pages.Internal.Script.Script theCliConfig ->
                    theCliConfig HtmlPrinter.htmlToString performRecord

        appInit : FlagsIncludingArgv flags -> cliOptions -> ( Model () msg, Cmd (Msg Never) )
        appInit flags cliOptions =
            init ( (), cliOptions ) flags
                |> Tuple.mapSecond (perform config)

        appUpdate : a -> Msg msg -> unknown -> ( unknown, Cmd (Msg Never) )
        appUpdate _ msg model =
            update msg model
                |> Tuple.mapSecond (perform config)

        appSubscriptions : a -> Sub (Msg Never)
        appSubscriptions _ =
            Sub.batch
                [ config.fromJsPort
                    |> Sub.map
                        (\jsonValue ->
                            let
                                decoder : Decode.Decoder (Msg Never)
                                decoder =
                                    Decode.field "tag" Decode.string
                                        |> Decode.andThen
                                            (\tag ->
                                                case tag of
                                                    "BuildError" ->
                                                        Decode.field "data"
                                                            (Decode.map2
                                                                (\message title ->
                                                                    { title = title
                                                                    , message = message
                                                                    , fatal = True
                                                                    , path = "" -- TODO wire in current path here
                                                                    }
                                                                )
                                                                (Decode.field "message" Decode.string |> Decode.map Terminal.fromAnsiString)
                                                                (Decode.field "title" Decode.string)
                                                            )
                                                            |> Decode.map GotBuildError

                                                    _ ->
                                                        Decode.fail "Unhandled msg"
                                            )
                            in
                            Decode.decodeValue decoder jsonValue
                                |> Result.mapError
                                    (\error ->
                                        ("From location 1: "
                                            ++ (error
                                                    |> Decode.errorToString
                                               )
                                        )
                                            |> BuildError.internal
                                            |> GotBuildError
                                    )
                                |> mergeResult
                        )
                , config.gotBatchSub |> Sub.map GotDataBatch
                ]

        programConfig :
            { printAndExitFailure : String -> Cmd msg
            , printAndExitSuccess : String -> Cmd msg
            , init : FlagsIncludingArgv flags -> cliOptions -> ( model, Cmd msg )
            , update : cliOptions -> msg -> model -> ( model, Cmd msg )
            , subscriptions : model -> Sub msg
            , config : Program.Config cliOptions
            }
        programConfig =
            { init = appInit
            , update = appUpdate
            , subscriptions = appSubscriptions
            , config = cliConfig
            , printAndExitFailure =
                \string ->
                    ToJsPayload.Errors
                        [ { title = "Invalid CLI arguments"
                          , path = ""
                          , message =
                                [ Terminal.text string
                                ]
                          , fatal = True
                          }
                        ]
                        |> Codec.encodeToValue (ToJsPayload.successCodecNew2 "" "")
                        |> config.toJsPort
                        |> Cmd.map never
            , printAndExitSuccess = \string -> config.toJsPort (Encode.string string) |> Cmd.map never
            }
    in
    Program.stateful programConfig


mergeResult : Result a a -> a
mergeResult r =
    case r of
        Ok rr ->
            rr

        Err rr ->
            rr


{-| -}
requestDecoder : Decode.Decoder Pages.StaticHttp.Request.Request
requestDecoder =
    Pages.StaticHttp.Request.codec
        |> Codec.decoder


flatten :
    { a
        | toJsPort : Encode.Value -> Cmd Never
        , fromJsPort : Sub Decode.Value
        , gotBatchSub : Sub Decode.Value
        , sendPageData : ToJsPayload.NewThingForPort -> Cmd Never
    }
    -> List Effect
    -> Cmd (Msg Never)
flatten config list =
    Cmd.batch (flattenHelp [] config list)


flattenHelp :
    List (Cmd (Msg Never))
    ->
        { a
            | toJsPort : Encode.Value -> Cmd Never
            , fromJsPort : Sub Decode.Value
            , gotBatchSub : Sub Decode.Value
            , sendPageData : ToJsPayload.NewThingForPort -> Cmd Never
        }
    -> List Effect
    -> List (Cmd (Msg Never))
flattenHelp soFar config list =
    case list of
        first :: rest ->
            flattenHelp
                (perform config first :: soFar)
                config
                rest

        [] ->
            soFar


perform :
    { a
        | toJsPort : Encode.Value -> Cmd Never
        , fromJsPort : Sub Decode.Value
        , gotBatchSub : Sub Decode.Value
        , sendPageData : ToJsPayload.NewThingForPort -> Cmd Never
    }
    -> Effect
    -> Cmd (Msg Never)
perform config effect =
    let
        canonicalSiteUrl : String
        canonicalSiteUrl =
            ""
    in
    case effect of
        Effect.NoEffect ->
            Cmd.none

        Effect.Batch list ->
            flatten config list

        Effect.FetchHttp requests ->
            requests
                |> List.map
                    (\request ->
                        ( Pages.StaticHttp.Request.hash request, request )
                    )
                |> ToJsPayload.DoHttp
                |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
                |> config.toJsPort
                |> Cmd.map never

        Effect.SendSinglePage info ->
            let
                currentPagePath : String
                currentPagePath =
                    case info of
                        ToJsPayload.PageProgress toJsSuccessPayloadNew ->
                            toJsSuccessPayloadNew.route

                        _ ->
                            ""
            in
            info
                |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl currentPagePath)
                |> config.toJsPort
                |> Cmd.map never

        Effect.SendSinglePageNew rawBytes info ->
            let
                currentPagePath : String
                currentPagePath =
                    case info of
                        ToJsPayload.PageProgress toJsSuccessPayloadNew ->
                            toJsSuccessPayloadNew.route

                        _ ->
                            ""
            in
            { oldThing =
                info
                    |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl currentPagePath)
            , binaryPageData = rawBytes
            }
                |> config.sendPageData
                |> Cmd.map never



-- TODO use Json.Decode.Value for flagsDecoder instead of hardcoded record flags
--flagsDecoder :
--    Decode.Decoder
--        { staticHttpCache : RequestsAndPending
--        , compatibilityKey : Int
--        }
--flagsDecoder =
--    Decode.map3
--        (\staticHttpCache compatibilityKey ->
--            { staticHttpCache = staticHttpCache
--            , isDevServer = isDevServer
--            , compatibilityKey = compatibilityKey
--            }
--        )
--        (Decode.succeed Dict.empty)
--        (Decode.field "compatibilityKey" Decode.int)


{-| -}
init :
    ( model, BackendTask FatalError () )
    -> FlagsIncludingArgv Flags
    -> ( Model model msg, Effect )
init ( model, execute ) flags =
    if flags.compatibilityKey == Pages.Internal.Platform.CompatibilityKey.currentCompatibilityKey then
        initLegacy model execute

    else
        let
            elmPackageAheadOfNpmPackage : Bool
            elmPackageAheadOfNpmPackage =
                Pages.Internal.Platform.CompatibilityKey.currentCompatibilityKey > flags.compatibilityKey

            message : String
            message =
                "The NPM package and Elm package you have installed are incompatible. If you are updating versions, be sure to update both the elm-pages Elm and NPM package.\n\n"
                    ++ (if elmPackageAheadOfNpmPackage then
                            "The elm-pages Elm package is ahead of the elm-pages NPM package. Try updating the elm-pages NPM package?"

                        else
                            "The elm-pages NPM package is ahead of the elm-pages Elm package. Try updating the elm-pages Elm package?"
                       )
        in
        updateAndSendPortIfDone
            { staticResponses = StaticResponses.empty ()
            , errors =
                [ { title = "Incompatible NPM and Elm package versions"
                  , message = [ Terminal.text <| message ]
                  , fatal = True
                  , path = ""
                  }
                ]
            , model = model
            }


initLegacy :
    model
    -> BackendTask FatalError ()
    -> ( Model model msg, Effect )
initLegacy model execute =
    let
        initialModel : Model model msg
        initialModel =
            { staticResponses = execute
            , errors = []
            , model = model
            }
    in
    StaticResponses.nextStep (Encode.object []) initialModel.staticResponses initialModel
        |> nextStepToEffect
            initialModel


updateAndSendPortIfDone :
    Model model msg
    -> ( Model model msg, Effect )
updateAndSendPortIfDone model =
    StaticResponses.nextStep (Encode.object [])
        model.staticResponses
        model
        |> nextStepToEffect model


{-| -}
update :
    Msg msg
    -> Model model msg
    -> ( Model model msg, Effect )
update msg model =
    case msg of
        GotDataBatch batch ->
            StaticResponses.nextStep batch
                model.staticResponses
                model
                |> nextStepToEffect model

        GotBuildError buildError ->
            let
                updatedModel : Model model msg
                updatedModel =
                    { model
                        | errors =
                            buildError :: model.errors
                    }
            in
            StaticResponses.nextStep (Encode.object [])
                updatedModel.staticResponses
                updatedModel
                |> nextStepToEffect updatedModel


nextStepToEffect :
    Model model
    -> StaticResponses.NextStep route ()
    -> ( Model model, Effect )
nextStepToEffect model nextStep =
    case nextStep of
        StaticResponses.Continue httpRequests updatedStaticResponsesModel ->
            ( { model
                | staticResponses = updatedStaticResponsesModel
              }
            , Effect.FetchHttp httpRequests
            )

        StaticResponses.Finish () ->
            ( model
            , { body = Encode.null
              , staticHttpCache = Dict.empty
              , statusCode = 200
              }
                |> ToJsPayload.SendApiResponse
                |> Effect.SendSinglePage
            )

        StaticResponses.FinishedWithErrors buildErrors ->
            ( model
            , buildErrors |> ToJsPayload.Errors |> Effect.SendSinglePage
            )
