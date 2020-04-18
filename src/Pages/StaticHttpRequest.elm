module Pages.StaticHttpRequest exposing (Error(..), Request(..), permanentError, resolve, resolveUrls, strippedResponses, toBuildError, urls)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Pages.Internal.ApplicationType as ApplicationType exposing (ApplicationType)
import Pages.StaticHttp.Request
import Secrets
import TerminalText as Terminal


type Request value
    = Request ( List (Secrets.Value Pages.StaticHttp.Request.Request), ApplicationType -> Dict String String -> Result Error ( Dict String String, Request value ) )
    | Done value


strippedResponses : ApplicationType -> Request value -> Dict String String -> Dict String String
strippedResponses appType request rawResponses =
    case request of
        Request ( list, lookupFn ) ->
            case lookupFn appType rawResponses of
                Err error ->
                    rawResponses

                Ok ( partiallyStrippedResponses, followupRequest ) ->
                    strippedResponses appType followupRequest partiallyStrippedResponses

        Done value ->
            rawResponses


type Error
    = MissingHttpResponse String
    | DecoderError String


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


permanentError : ApplicationType -> Request value -> Dict String String -> Maybe Error
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

        Done value ->
            Nothing


resolve : ApplicationType -> Request value -> Dict String String -> Result Error value
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


resolveUrls : ApplicationType -> Request value -> Dict String String -> ( Bool, List (Secrets.Value Pages.StaticHttp.Request.Request) )
resolveUrls appType request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn appType rawResponses of
                Ok ( partiallyStrippedResponses, nextRequest ) ->
                    resolveUrls appType nextRequest rawResponses
                        |> Tuple.mapSecond ((++) urlList)

                Err error ->
                    ( False
                    , urlList
                    )

        Done value ->
            ( True, [] )
