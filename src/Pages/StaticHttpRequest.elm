module Pages.StaticHttpRequest exposing (Error(..), RawRequest(..), Status(..), cacheRequestResolution, resolve, resolveUrls, strippedResponses, toBuildError)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Pages.Internal.ApplicationType exposing (ApplicationType)
import Pages.StaticHttp.Request
import RequestsAndPending exposing (RequestsAndPending)
import Secrets
import TerminalText as Terminal


type RawRequest value
    = Request
        ( List (Secrets.Value Pages.StaticHttp.Request.Request)
        , ApplicationType -> RequestsAndPending -> Result Error ( Dict String String, RawRequest value )
        )
    | Done value


strippedResponses : ApplicationType -> RawRequest value -> RequestsAndPending -> Dict String String
strippedResponses =
    strippedResponsesHelp Dict.empty


strippedResponsesHelp : Dict String String -> ApplicationType -> RawRequest value -> RequestsAndPending -> Dict String String
strippedResponsesHelp usedSoFar appType request rawResponses =
    case request of
        Request ( _, lookupFn ) ->
            case lookupFn appType rawResponses of
                Err _ ->
                    usedSoFar

                Ok ( partiallyStrippedResponses, followupRequest ) ->
                    strippedResponsesHelp (Dict.union usedSoFar partiallyStrippedResponses) appType followupRequest rawResponses

        Done _ ->
            usedSoFar


type Error
    = MissingHttpResponse String
    | DecoderError String
    | UserCalledStaticHttpFail String


toBuildError : String -> Error -> BuildError
toBuildError path error =
    case error of
        MissingHttpResponse missingKey ->
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
        Request ( _, lookupFn ) ->
            case lookupFn appType rawResponses of
                Ok ( _, nextRequest ) ->
                    resolve appType nextRequest rawResponses

                Err error ->
                    Err error

        Done value ->
            Ok value


resolveUrls : ApplicationType -> RawRequest value -> RequestsAndPending -> ( Bool, List (Secrets.Value Pages.StaticHttp.Request.Request) )
resolveUrls appType request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn appType rawResponses of
                Ok ( _, nextRequest ) ->
                    resolveUrls appType nextRequest rawResponses
                        |> Tuple.mapSecond ((++) urlList)

                Err _ ->
                    ( False
                    , urlList
                    )

        Done _ ->
            ( True, [] )


cacheRequestResolution :
    ApplicationType
    -> RawRequest value
    -> RequestsAndPending
    -> Status value
cacheRequestResolution =
    cacheRequestResolutionHelp []


type Status value
    = Incomplete (List (Secrets.Value Pages.StaticHttp.Request.Request))
    | HasPermanentError Error
    | Complete


cacheRequestResolutionHelp :
    List (Secrets.Value Pages.StaticHttp.Request.Request)
    -> ApplicationType
    -> RawRequest value
    -> RequestsAndPending
    -> Status value
cacheRequestResolutionHelp foundUrls appType request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn appType rawResponses of
                Ok ( _, nextRequest ) ->
                    cacheRequestResolutionHelp urlList appType nextRequest rawResponses

                Err error ->
                    case error of
                        MissingHttpResponse _ ->
                            Incomplete (urlList ++ foundUrls)

                        DecoderError _ ->
                            HasPermanentError error

                        UserCalledStaticHttpFail _ ->
                            HasPermanentError error

        Done _ ->
            Complete
