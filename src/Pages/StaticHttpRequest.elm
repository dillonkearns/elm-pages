module Pages.StaticHttpRequest exposing (Error(..), RawRequest(..), Status(..), cacheRequestResolution, resolve, resolveUrls, strippedResponsesEncode, toBuildError)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import List.Extra
import Pages.StaticHttp.Request
import RequestsAndPending exposing (RequestsAndPending)
import Set exposing (Set)
import TerminalText as Terminal


type RawRequest value
    = Request (Set String) ( List Pages.StaticHttp.Request.Request, RequestsAndPending -> RawRequest value )
    | RequestError Error
    | ApiRoute (Set String) value


strippedResponses : RawRequest value -> RequestsAndPending -> Set String
strippedResponses =
    strippedResponsesHelp Set.empty


strippedResponsesEncode : RawRequest value -> RequestsAndPending -> Result (List BuildError) (Dict String String)
strippedResponsesEncode rawRequest requestsAndPending =
    strippedResponses rawRequest requestsAndPending
        |> Set.toList
        |> List.map
            (\k ->
                (Dict.get k requestsAndPending
                    |> Maybe.withDefault Nothing
                    |> Maybe.withDefault ""
                    |> Just
                    |> Ok
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


strippedResponsesHelp : Set String -> RawRequest value -> RequestsAndPending -> Set String
strippedResponsesHelp usedSoFar request rawResponses =
    case request of
        RequestError _ ->
            usedSoFar

        Request partiallyStrippedResponses ( _, lookupFn ) ->
            case lookupFn rawResponses of
                followupRequest ->
                    strippedResponsesHelp
                        (Set.union
                            usedSoFar
                            partiallyStrippedResponses
                        )
                        followupRequest
                        rawResponses

        ApiRoute partiallyStrippedResponses _ ->
            Set.union
                usedSoFar
                partiallyStrippedResponses


type Error
    = MissingHttpResponse String (List Pages.StaticHttp.Request.Request)
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


resolve : RawRequest value -> RequestsAndPending -> Result Error value
resolve request rawResponses =
    case request of
        RequestError error ->
            Err error

        Request _ ( _, lookupFn ) ->
            case lookupFn rawResponses of
                nextRequest ->
                    resolve nextRequest rawResponses

        ApiRoute _ value ->
            Ok value


resolveUrls : RawRequest value -> RequestsAndPending -> List Pages.StaticHttp.Request.Request
resolveUrls request rawResponses =
    resolveUrlsHelp rawResponses [] request


resolveUrlsHelp : RequestsAndPending -> List Pages.StaticHttp.Request.Request -> RawRequest value -> List Pages.StaticHttp.Request.Request
resolveUrlsHelp rawResponses soFar request =
    case request of
        RequestError error ->
            case error of
                MissingHttpResponse _ next ->
                    (soFar ++ next)
                        |> List.Extra.uniqueBy Pages.StaticHttp.Request.hash

                _ ->
                    soFar

        Request _ ( urlList, lookupFn ) ->
            resolveUrlsHelp
                rawResponses
                (soFar ++ urlList)
                (lookupFn rawResponses)

        ApiRoute _ _ ->
            soFar


cacheRequestResolution :
    RawRequest value
    -> RequestsAndPending
    -> Status value
cacheRequestResolution request rawResponses =
    cacheRequestResolutionHelp [] rawResponses request


type Status value
    = Incomplete (List Pages.StaticHttp.Request.Request)
    | HasPermanentError Error
    | Complete


cacheRequestResolutionHelp :
    List Pages.StaticHttp.Request.Request
    -> RequestsAndPending
    -> RawRequest value
    -> Status value
cacheRequestResolutionHelp foundUrls rawResponses request =
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
                rawResponses
                (lookupFn rawResponses)

        ApiRoute _ _ ->
            Complete
