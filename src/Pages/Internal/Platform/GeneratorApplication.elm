module Pages.Internal.Platform.GeneratorApplication exposing (Flags, Model, Msg(..), init, requestDecoder, update, app)

{-| Exposed for internal use only (used in generated code).

@docs Flags, Model, Msg, init, requestDecoder, update, app

-}

import BuildError exposing (BuildError)
import Cli.Program as Program exposing (FlagsIncludingArgv)
import Codec
import DataSource exposing (DataSource)
import Dict
import HtmlPrinter
import Json.Decode as Decode
import Json.Encode
import Pages.GeneratorProgramConfig exposing (GeneratorProgramConfig)
import Pages.Internal.Platform.CompatibilityKey
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.StaticResponses as StaticResponses exposing (StaticResponses)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload
import Pages.Internal.Script
import Pages.StaticHttp.Request
import RequestsAndPending exposing (RequestsAndPending)
import TerminalText as Terminal


{-| -}
type alias Flags =
    { compatibilityKey : Int
    }


{-| -}
type alias Model =
    { staticResponses : StaticResponses
    , errors : List BuildError
    , allRawResponses : RequestsAndPending
    , done : Bool
    }


{-| -}
type Msg
    = GotDataBatch
        (List
            { request : Pages.StaticHttp.Request.Request
            , response : RequestsAndPending.Response
            }
        )
    | GotBuildError BuildError


{-| -}
app :
    GeneratorProgramConfig
    -> Program.StatefulProgram Model Msg (DataSource ()) Flags
app config =
    let
        cliConfig : Program.Config (DataSource ())
        cliConfig =
            case config.data of
                Pages.Internal.Script.Script theCliConfig ->
                    theCliConfig HtmlPrinter.htmlToString
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
            \_ ->
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
                    , config.gotBatchSub
                        |> Sub.map
                            (\newBatch ->
                                Decode.decodeValue batchDecoder newBatch
                                    |> Result.map GotDataBatch
                                    |> Result.mapError
                                        (\error ->
                                            ("From location 2: "
                                                ++ (error
                                                        |> Decode.errorToString
                                                   )
                                            )
                                                |> BuildError.internal
                                                |> GotBuildError
                                        )
                                    |> mergeResult
                            )
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
                    |> config.toJsPort
                    |> Cmd.map never
        , printAndExitSuccess = \string -> config.toJsPort (Json.Encode.string string) |> Cmd.map never
        }


batchDecoder : Decode.Decoder (List { request : Pages.StaticHttp.Request.Request, response : RequestsAndPending.Response })
batchDecoder =
    Decode.map2 (\request response -> { request = request, response = response })
        (Decode.field "request" requestDecoder)
        (Decode.field "response" RequestsAndPending.decoder)
        |> Decode.list


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

        Effect.FetchHttp unmasked ->
            ToJsPayload.DoHttp unmasked unmasked.useCache
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

        Effect.Continue ->
            Cmd.none



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
    DataSource ()
    -> FlagsIncludingArgv Flags
    -> ( Model, Effect )
init execute flags =
    if flags.compatibilityKey == Pages.Internal.Platform.CompatibilityKey.currentCompatibilityKey then
        initLegacy execute { staticHttpCache = Dict.empty }

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
            { staticResponses = StaticResponses.empty
            , errors =
                [ { title = "Incompatible NPM and Elm package versions"
                  , message = [ Terminal.text <| message ]
                  , fatal = True
                  , path = ""
                  }
                ]
            , allRawResponses = Dict.empty
            , done = False
            }


initLegacy :
    DataSource ()
    -> { staticHttpCache : RequestsAndPending }
    -> ( Model, Effect )
initLegacy execute { staticHttpCache } =
    let
        staticResponses : StaticResponses
        staticResponses =
            StaticResponses.renderApiRequest execute

        initialModel : Model
        initialModel =
            { staticResponses = staticResponses
            , errors = []
            , allRawResponses = staticHttpCache
            , done = False
            }
    in
    StaticResponses.nextStep initialModel Nothing
        |> nextStepToEffect
            initialModel


updateAndSendPortIfDone :
    Model
    -> ( Model, Effect )
updateAndSendPortIfDone model =
    StaticResponses.nextStep
        model
        Nothing
        |> nextStepToEffect model


{-| -}
update :
    Msg
    -> Model
    -> ( Model, Effect )
update msg model =
    case msg of
        GotDataBatch batch ->
            let
                updatedModel : Model
                updatedModel =
                    model
                        |> StaticResponses.batchUpdate batch
            in
            StaticResponses.nextStep
                updatedModel
                Nothing
                |> nextStepToEffect updatedModel

        GotBuildError buildError ->
            let
                updatedModel : Model
                updatedModel =
                    { model
                        | errors =
                            buildError :: model.errors
                    }
            in
            StaticResponses.nextStep
                updatedModel
                Nothing
                |> nextStepToEffect updatedModel


nextStepToEffect :
    Model
    -> ( StaticResponses, StaticResponses.NextStep route )
    -> ( Model, Effect )
nextStepToEffect model ( updatedStaticResponsesModel, nextStep ) =
    case nextStep of
        StaticResponses.Continue _ httpRequests _ ->
            let
                updatedModel : Model
                updatedModel =
                    { model
                        | allRawResponses = Dict.empty
                        , staticResponses = updatedStaticResponsesModel
                    }
            in
            if List.isEmpty httpRequests then
                nextStepToEffect
                    updatedModel
                    (StaticResponses.nextStep
                        updatedModel
                        Nothing
                    )

            else
                ( updatedModel
                , (httpRequests
                    |> List.map Effect.FetchHttp
                  )
                    |> Effect.Batch
                )

        StaticResponses.Finish toJsPayload ->
            case toJsPayload of
                StaticResponses.ApiResponse ->
                    ( model
                    , { body = Json.Encode.null
                      , staticHttpCache = Dict.empty
                      , statusCode = 200
                      }
                        |> ToJsPayload.SendApiResponse
                        |> Effect.SendSinglePage
                    )

                StaticResponses.Errors errors ->
                    ( model
                    , errors |> ToJsPayload.Errors |> Effect.SendSinglePage
                    )
