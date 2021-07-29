module Pages.StaticHttpRequest exposing (Error(..), RawRequest(..), Status(..), WhatToDo(..), cacheRequestResolution, merge, resolve, resolveUrls, strippedResponsesEncode, toBuildError)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Internal.OptimizedDecoder
import Json.Decode.Exploration
import Json.Encode
import KeepOrDiscard exposing (KeepOrDiscard)
import List.Extra
import OptimizedDecoder
import Pages.Internal.ApplicationType exposing (ApplicationType)
import Pages.StaticHttp.Request
import RequestsAndPending exposing (RequestsAndPending)
import Secrets
import TerminalText as Terminal


type RawRequest value
    = Request (Dict String WhatToDo) ( List (Secrets.Value Pages.StaticHttp.Request.Request), KeepOrDiscard -> ApplicationType -> RequestsAndPending -> RawRequest value )
    | RequestError Error
    | Done (Dict String WhatToDo) value


type WhatToDo
    = UseRawResponse
    | CliOnly
    | StripResponse (OptimizedDecoder.Decoder ())
    | DistilledResponse Json.Encode.Value
    | Error (List BuildError)


merge : String -> WhatToDo -> WhatToDo -> WhatToDo
merge key whatToDo1 whatToDo2 =
    case ( whatToDo1, whatToDo2 ) of
        ( Error buildErrors1, Error buildErrors2 ) ->
            Error (buildErrors1 ++ buildErrors2)

        ( Error buildErrors1, _ ) ->
            Error buildErrors1

        ( _, Error buildErrors1 ) ->
            Error buildErrors1

        ( StripResponse strip1, StripResponse strip2 ) ->
            StripResponse (OptimizedDecoder.map2 (\_ _ -> ()) strip1 strip2)

        ( StripResponse strip1, _ ) ->
            StripResponse strip1

        ( _, StripResponse strip1 ) ->
            StripResponse strip1

        ( _, CliOnly ) ->
            whatToDo1

        ( CliOnly, _ ) ->
            whatToDo2

        ( DistilledResponse distilled1, DistilledResponse distilled2 ) ->
            if Json.Encode.encode 0 distilled1 == Json.Encode.encode 0 distilled2 then
                DistilledResponse distilled1

            else
                Error
                    [ { title = "Non-Unique Distill Keys"
                      , message =
                            [ Terminal.text "I encountered DataSource.distill with two matching keys that had differing encoded values.\n\n"
                            , Terminal.text "Look for "
                            , Terminal.red <| "DataSource.distill"
                            , Terminal.text " with the key "
                            , Terminal.red <| ("\"" ++ key ++ "\"")
                            , Terminal.text "\n\n"
                            , Terminal.yellow <| "The first encoded value was:\n"
                            , Terminal.text <| Json.Encode.encode 2 distilled1
                            , Terminal.text "\n\n-------------------------------\n\n"
                            , Terminal.yellow <| "The second encoded value was:\n"
                            , Terminal.text <| Json.Encode.encode 2 distilled2
                            ]
                      , path = "" -- TODO wire in path here?
                      , fatal = True
                      }
                    ]

        ( DistilledResponse distilled1, _ ) ->
            DistilledResponse distilled1

        ( _, DistilledResponse distilled1 ) ->
            DistilledResponse distilled1

        ( UseRawResponse, UseRawResponse ) ->
            UseRawResponse


strippedResponses : ApplicationType -> RawRequest value -> RequestsAndPending -> Dict String WhatToDo
strippedResponses =
    strippedResponsesHelp Dict.empty


strippedResponsesEncode : ApplicationType -> RawRequest value -> RequestsAndPending -> Result (List BuildError) (Dict String String)
strippedResponsesEncode appType rawRequest requestsAndPending =
    strippedResponses appType rawRequest requestsAndPending
        |> Dict.toList
        |> List.map
            (\( k, whatToDo ) ->
                (case whatToDo of
                    UseRawResponse ->
                        Dict.get k requestsAndPending
                            |> Maybe.withDefault Nothing
                            |> Maybe.withDefault ""
                            |> Just
                            |> Ok

                    StripResponse decoder ->
                        Dict.get k requestsAndPending
                            |> Maybe.withDefault Nothing
                            |> Maybe.withDefault ""
                            |> Json.Decode.Exploration.stripString (Internal.OptimizedDecoder.jde decoder)
                            |> Result.withDefault "ERROR"
                            |> Just
                            |> Ok

                    CliOnly ->
                        Nothing
                            |> Ok

                    DistilledResponse value ->
                        value
                            |> Json.Encode.encode 0
                            |> Just
                            |> Ok

                    Error buildError ->
                        Err buildError
                )
                    |> Result.map (Maybe.map (Tuple.pair k))
            )
        |> combineMultipleErrors
        |> Result.map (List.filterMap identity)
        |> Result.map Dict.fromList


combineMultipleErrors : List (Result (List error) a) -> Result (List error) (List a)
combineMultipleErrors results =
    List.foldr
        (\result soFarResult ->
            case soFarResult of
                Ok soFarOk ->
                    case result of
                        Ok value ->
                            value :: soFarOk |> Ok

                        Err error_ ->
                            Err error_

                Err errorsSoFar ->
                    case result of
                        Ok _ ->
                            Err errorsSoFar

                        Err error_ ->
                            Err <| error_ ++ errorsSoFar
        )
        (Ok [])
        results


strippedResponsesHelp : Dict String WhatToDo -> ApplicationType -> RawRequest value -> RequestsAndPending -> Dict String WhatToDo
strippedResponsesHelp usedSoFar appType request rawResponses =
    case request of
        RequestError _ ->
            usedSoFar

        Request partiallyStrippedResponses ( _, lookupFn ) ->
            case lookupFn KeepOrDiscard.Keep appType rawResponses of
                followupRequest ->
                    strippedResponsesHelp
                        (Dict.merge
                            (\key a -> Dict.insert key a)
                            (\key a b -> Dict.insert key (merge key a b))
                            (\key b -> Dict.insert key b)
                            usedSoFar
                            partiallyStrippedResponses
                            Dict.empty
                        )
                        appType
                        followupRequest
                        rawResponses

        Done partiallyStrippedResponses _ ->
            Dict.merge
                (\key a -> Dict.insert key a)
                (\key a b -> Dict.insert key (merge key a b))
                (\key b -> Dict.insert key b)
                usedSoFar
                partiallyStrippedResponses
                Dict.empty


type Error
    = MissingHttpResponse String (List (Secrets.Value Pages.StaticHttp.Request.Request))
    | DecoderError String
    | UserCalledStaticHttpFail String


toBuildError : String -> Error -> BuildError
toBuildError path error =
    case error of
        MissingHttpResponse missingKey _ ->
            { title = "Missing Http Response"
            , message =
                [ Terminal.text missingKey
                ]
            , path = path
            , fatal = True
            }

        DecoderError decodeErrorMessage ->
            { title = "Static Http Decoding Error"
            , message =
                [ Terminal.text decodeErrorMessage
                ]
            , path = path
            , fatal = True
            }

        UserCalledStaticHttpFail decodeErrorMessage ->
            { title = "Called Static Http Fail"
            , message =
                [ Terminal.text <| "I ran into a call to `DataSource.fail` with message: " ++ decodeErrorMessage
                ]
            , path = path
            , fatal = True
            }


resolve : ApplicationType -> RawRequest value -> RequestsAndPending -> Result Error value
resolve appType request rawResponses =
    case request of
        RequestError error ->
            Err error

        Request _ ( _, lookupFn ) ->
            case lookupFn KeepOrDiscard.Keep appType rawResponses of
                nextRequest ->
                    resolve appType nextRequest rawResponses

        Done _ value ->
            Ok value


resolveUrls : ApplicationType -> RawRequest value -> RequestsAndPending -> List (Secrets.Value Pages.StaticHttp.Request.Request)
resolveUrls appType request rawResponses =
    resolveUrlsHelp appType rawResponses [] request


resolveUrlsHelp : ApplicationType -> RequestsAndPending -> List (Secrets.Value Pages.StaticHttp.Request.Request) -> RawRequest value -> List (Secrets.Value Pages.StaticHttp.Request.Request)
resolveUrlsHelp appType rawResponses soFar request =
    case request of
        RequestError error ->
            case error of
                MissingHttpResponse _ next ->
                    (soFar ++ next)
                        |> List.Extra.uniqueBy (Secrets.maskedLookup >> Pages.StaticHttp.Request.hash)

                _ ->
                    soFar

        Request _ ( urlList, lookupFn ) ->
            resolveUrlsHelp appType
                rawResponses
                (soFar ++ urlList)
                (lookupFn KeepOrDiscard.Keep appType rawResponses)

        Done _ _ ->
            soFar


cacheRequestResolution :
    ApplicationType
    -> RawRequest value
    -> RequestsAndPending
    -> Status value
cacheRequestResolution appType request rawResponses =
    cacheRequestResolutionHelp [] appType rawResponses request


type Status value
    = Incomplete (List (Secrets.Value Pages.StaticHttp.Request.Request))
    | HasPermanentError Error
    | Complete


cacheRequestResolutionHelp :
    List (Secrets.Value Pages.StaticHttp.Request.Request)
    -> ApplicationType
    -> RequestsAndPending
    -> RawRequest value
    -> Status value
cacheRequestResolutionHelp foundUrls appType rawResponses request =
    case request of
        RequestError error ->
            case error of
                MissingHttpResponse _ _ ->
                    -- TODO do I need to pass through continuation URLs here? -- Incomplete (urlList ++ foundUrls)
                    Incomplete foundUrls

                DecoderError _ ->
                    HasPermanentError error

                UserCalledStaticHttpFail _ ->
                    HasPermanentError error

        Request _ ( urlList, lookupFn ) ->
            cacheRequestResolutionHelp urlList
                appType
                rawResponses
                (lookupFn KeepOrDiscard.Keep appType rawResponses)

        Done _ _ ->
            Complete
