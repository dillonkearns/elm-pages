module Pages.StaticHttpRequest exposing (Error(..), Request(..), permanentError, resolve, resolveUrls, strippedResponses, toBuildError, urls)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Secrets
import TerminalText as Terminal


type Request value
    = Request ( List (Secrets.Value { url : String, method : String, headers : List ( String, String ) }), Dict String String -> Result Error ( Dict String String, Request value ) )
    | Done value


strippedResponses : Request value -> Dict String String -> Dict String String
strippedResponses request rawResponses =
    case request of
        Request ( list, lookupFn ) ->
            case lookupFn rawResponses of
                Err error ->
                    rawResponses

                Ok ( partiallyStrippedResponses, followupRequest ) ->
                    strippedResponses followupRequest partiallyStrippedResponses

        Done value ->
            rawResponses


type Error
    = MissingHttpResponse String
    | DecoderError String


type alias RequestDetails =
    { url : String, method : String, headers : List ( String, String ) }


urls : Request value -> List (Secrets.Value RequestDetails)
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
            }

        DecoderError decodeErrorMessage ->
            { title = "Static Http Decoding Error"
            , message =
                [ Terminal.text path
                , Terminal.text "\n\n"
                , Terminal.text decodeErrorMessage
                ]
            }


permanentError : Request value -> Dict String String -> Maybe Error
permanentError request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn rawResponses of
                Ok ( partiallyStrippedResponses, nextRequest ) ->
                    permanentError nextRequest rawResponses

                Err error ->
                    case error of
                        MissingHttpResponse _ ->
                            Nothing

                        DecoderError _ ->
                            Just error

        Done value ->
            Nothing


resolve : Request value -> Dict String String -> Result Error value
resolve request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn rawResponses of
                Ok ( partiallyStrippedResponses, nextRequest ) ->
                    resolve nextRequest rawResponses

                Err error ->
                    Err error

        Done value ->
            Ok value


resolveUrls : Request value -> Dict String String -> ( Bool, List (Secrets.Value RequestDetails) )
resolveUrls request rawResponses =
    case request of
        Request ( urlList, lookupFn ) ->
            case lookupFn rawResponses of
                Ok ( partiallyStrippedResponses, nextRequest ) ->
                    resolveUrls nextRequest rawResponses
                        |> Tuple.mapSecond ((++) urlList)

                Err error ->
                    ( False
                    , urlList
                    )

        Done value ->
            ( True, [] )
