module Pages.StaticHttpRequest exposing (Error(..), Request(..), Status(..), cacheRequestResolution, permanentError, resolve, resolveUrls, strippedResponses, toBuildError, urls)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Pages.Internal.ApplicationType as ApplicationType exposing (ApplicationType)
import Pages.Internal.StaticHttpBody as StaticHttpBody
import Pages.StaticHttp.Request
import RequestsAndPending exposing (RequestsAndPending)
import Secrets
import TerminalText as Terminal


type Request value
    = Request ( List (Secrets.Value Pages.StaticHttp.Request.Request), ApplicationType -> RequestsAndPending -> Result Error ( Dict String String, Request value ) )
    | Done value


strippedResponses : ApplicationType -> Request value -> RequestsAndPending -> Dict String String
strippedResponses =
    strippedResponsesHelp Dict.empty


strippedResponsesHelp : Dict String String -> ApplicationType -> Request value -> RequestsAndPending -> Dict String String
strippedResponsesHelp usedSoFar appType request rawResponses =
    case request of
        Request ( list, lookupFn ) ->
            case lookupFn appType rawResponses of
                Err error ->
                    usedSoFar

                Ok ( partiallyStrippedResponses, followupRequest ) ->
                    strippedResponsesHelp (Dict.union usedSoFar partiallyStrippedResponses) appType followupRequest rawResponses

        Done value ->
            usedSoFar


type Error
    = MissingHttpResponse String
    | DecoderError String
    | UserCalledStaticHttpFail String


urls : Request value -> List (Secrets.Value Pages.StaticHttp.Request.Request)
urls request =
    case request of
        Request ( urlList, lookupFn ) ->
            urlList

        Done value ->
            []


toBuildError : String -> Error -> BuildError
toBuildError path error =
    case error of
        MissingHttpResponse missingKey ->
            { title = "Missing Http Response"
            , message =
                [ Terminal.text path
                , Terminal.text "\n\n"
                , Terminal.text missingKey
                ]
            , fatal = True
            }

        DecoderError decodeErrorMessage ->
            { title = "Static Http Decoding Error"
            , message =
                [ Terminal.text path
                , Terminal.text "\n\n"
                , Terminal.text decodeErrorMessage
                ]
            , fatal = True
            }

        UserCalledStaticHttpFail decodeErrorMessage ->
            { title = "Called Static Http Fail"
            , message =
                [ Terminal.text path
                , Terminal.text "\n\n"
                , Terminal.text <| "I ran into a call to `Pages.StaticHttp.fail` with message: " ++ decodeErrorMessage
                ]
            , fatal = True
            }


permanentError : ApplicationType -> Request value -> RequestsAndPending -> Maybe Error
permanentError appType request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn appType rawResponses of
                Ok ( partiallyStrippedResponses, nextRequest ) ->
                    permanentError appType nextRequest rawResponses

                Err error ->
                    case error of
                        MissingHttpResponse _ ->
                            Nothing

                        DecoderError _ ->
                            Just error

                        UserCalledStaticHttpFail string ->
                            Just error

        Done value ->
            Nothing


resolve : ApplicationType -> Request value -> RequestsAndPending -> Result Error value
resolve appType request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn appType rawResponses of
                Ok ( partiallyStrippedResponses, nextRequest ) ->
                    resolve appType nextRequest rawResponses

                Err error ->
                    Err error

        Done value ->
            Ok value


resolveUrls : ApplicationType -> Request value -> RequestsAndPending -> ( Bool, List (Secrets.Value Pages.StaticHttp.Request.Request) )
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
    -> Request value
    -> RequestsAndPending
    -> Status value
cacheRequestResolution =
    cacheRequestResolutionHelp []


type Status value
    = Incomplete (List (Secrets.Value Pages.StaticHttp.Request.Request))
    | HasPermanentError Error
    | Complete value -- TODO include stripped responses?


cacheRequestResolutionHelp :
    List (Secrets.Value Pages.StaticHttp.Request.Request)
    -> ApplicationType
    -> Request value
    -> RequestsAndPending
    -> Status value
cacheRequestResolutionHelp foundUrls appType request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn appType rawResponses of
                Ok ( partiallyStrippedResponses, nextRequest ) ->
                    cacheRequestResolutionHelp urlList appType nextRequest rawResponses

                Err error ->
                    case error of
                        MissingHttpResponse string ->
                            Incomplete (urlList ++ foundUrls)

                        DecoderError string ->
                            HasPermanentError error

                        UserCalledStaticHttpFail string ->
                            HasPermanentError error

        Done value ->
            Complete value
