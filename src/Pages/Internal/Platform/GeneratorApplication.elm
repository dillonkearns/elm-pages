module Pages.Internal.Platform.GeneratorApplication exposing (Program, Flags, Model, Msg(..), init, requestDecoder, update, app, JsonValue)

{-| Exposed for internal use only (used in generated code).

@docs Program, Flags, Model, Msg, init, requestDecoder, update, app, JsonValue

-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import BuildError exposing (BuildError)
import Bytes exposing (Bytes)
import Cli.OptionsParser as OptionsParser
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
import Pages.Internal.StaticHttpBody
import Pages.StaticHttp.Request
import RequestsAndPending
import TerminalText as Terminal


{-| -}
type alias JsonValue =
    Decode.Value


{-| -}
type alias Program =
    Program.StatefulProgram Model Msg (BackendTask FatalError ()) Flags


{-| -}
type alias Flags =
    { compatibilityKey : Int
    }


{-| -}
type alias Model =
    { staticResponses : BackendTask FatalError ()
    , errors : List BuildError
    }


{-| -}
type Msg
    = GotDataBatch (List { key : String, json : Decode.Value, bytes : Maybe Bytes })
    | GotBuildError BuildError


{-| -}
app :
    GeneratorProgramConfig
    -> Program
app config =
    let
        baseCliConfig : Program.Config (BackendTask FatalError ())
        baseCliConfig =
            case config.data of
                Pages.Internal.Script.Script script ->
                    script.toConfig HtmlPrinter.htmlToString

        cliConfig : Program.Config (BackendTask FatalError ())
        cliConfig =
            case
                Pages.Internal.Script.metadata
                    { moduleName = config.scriptModuleName
                    , path = ""
                    }
                    config.data
            of
                Just metadata ->
                    baseCliConfig
                        |> Program.add
                            (OptionsParser.build
                                (logInternal
                                    (metadata
                                        |> Encode.encode 0
                                    )
                                )
                                |> OptionsParser.expectFlag "introspect-cli"
                            )

                Nothing ->
                    baseCliConfig
    in
    Program.stateful
        { init =
            \flags cliOptions ->
                init cliOptions flags
                    |> Tuple.mapSecond (perform config)
        , update =
            \_ msg model ->
                update msg model
                    |> Tuple.mapSecond (perform config)
        , subscriptions =
            \_ _ ->
                Sub.batch
                    [ config.fromJsPort
                        |> Sub.map
                            (\jsonValue ->
                                let
                                    decoder : Decode.Decoder Msg
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
                    |> (\json -> config.toJsPort { json = json, bytes = [] })
                    |> Cmd.map never
        , printAndExitSuccess = \string -> config.toJsPort { json = Encode.string string, bytes = [] } |> Cmd.map never
        }


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


flatten : GeneratorProgramConfig -> List Effect -> Cmd Msg
flatten config list =
    Cmd.batch (flattenHelp [] config list)


flattenHelp : List (Cmd Msg) -> GeneratorProgramConfig -> List Effect -> List (Cmd Msg)
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
    GeneratorProgramConfig
    -> Effect
    -> Cmd Msg
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
            let
                requestsWithHashes : List ( String, Pages.StaticHttp.Request.Request )
                requestsWithHashes =
                    requests
                        |> List.map
                            (\request ->
                                ( Pages.StaticHttp.Request.hash request, request )
                            )

                bytesPayloads : List { key : String, data : Bytes }
                bytesPayloads =
                    requestsWithHashes
                        |> List.concatMap
                            (\( hash, request ) ->
                                Pages.Internal.StaticHttpBody.extractAllBytes hash request.body
                            )

                jsonPayload : Encode.Value
                jsonPayload =
                    requestsWithHashes
                        |> ToJsPayload.DoHttp
                        |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl "")
            in
            config.toJsPort { json = jsonPayload, bytes = bytesPayloads }
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
            config.toJsPort
                { json = info |> Codec.encoder (ToJsPayload.successCodecNew2 canonicalSiteUrl currentPagePath)
                , bytes = []
                }
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


logInternal : String -> BackendTask FatalError ()
logInternal message =
    BackendTask.Internal.Request.request
        { name = "log"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "message", Encode.string message )
                    ]
                )
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }



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
    BackendTask FatalError ()
    -> FlagsIncludingArgv Flags
    -> ( Model, Effect )
init execute flags =
    if flags.compatibilityKey == Pages.Internal.Platform.CompatibilityKey.currentCompatibilityKey then
        initLegacy execute

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
            }


initLegacy :
    BackendTask FatalError ()
    -> ( Model, Effect )
initLegacy execute =
    let
        initialModel : Model
        initialModel =
            { staticResponses = execute
            , errors = []
            }
    in
    StaticResponses.nextStep RequestsAndPending.empty initialModel.staticResponses initialModel
        |> nextStepToEffect
            initialModel


updateAndSendPortIfDone :
    Model
    -> ( Model, Effect )
updateAndSendPortIfDone model =
    StaticResponses.nextStep RequestsAndPending.empty
        model.staticResponses
        model
        |> nextStepToEffect model


{-| -}
update :
    Msg
    -> Model
    -> ( Model, Effect )
update msg model =
    case msg of
        GotDataBatch entries ->
            let
                batch : RequestsAndPending.RequestsAndPending
                batch =
                    { json = Encode.object (List.map (\e -> ( e.key, e.json )) entries)
                    , rawBytes =
                        entries
                            |> List.filterMap (\e -> Maybe.map (\b -> ( e.key, b )) e.bytes)
                            |> Dict.fromList
                    }
            in
            StaticResponses.nextStep batch
                model.staticResponses
                model
                |> nextStepToEffect model

        GotBuildError buildError ->
            let
                updatedModel : Model
                updatedModel =
                    { model
                        | errors =
                            buildError :: model.errors
                    }
            in
            StaticResponses.nextStep RequestsAndPending.empty
                updatedModel.staticResponses
                updatedModel
                |> nextStepToEffect updatedModel


nextStepToEffect :
    Model
    -> StaticResponses.NextStep route ()
    -> ( Model, Effect )
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
