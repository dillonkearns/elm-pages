module Pages.StaticHttpRequest exposing (Error(..), RawRequest(..), Status(..), WhatToDo(..), cacheRequestResolution, merge, resolve, resolveUrls, strippedResponsesEncode, toBuildError)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import List.Extra
import Pages.Internal.ApplicationType exposing (ApplicationType)
import Pages.StaticHttp.Request
import RequestsAndPending exposing (RequestsAndPending)
import TerminalText as Terminal


type RawRequest value
    = Request (Dict String WhatToDo) ( List Pages.StaticHttp.Request.Request, ApplicationType -> RequestsAndPending -> RawRequest value )
    | RequestError Error
    | ApiRoute (Dict String WhatToDo) value


type WhatToDo
    = UseRawResponse


merge : String -> WhatToDo -> WhatToDo -> WhatToDo
merge _ _ _ =
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
            case lookupFn appType rawResponses of
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

        ApiRoute partiallyStrippedResponses _ ->
            Dict.merge
                (\key a -> Dict.insert key a)
                (\key a b -> Dict.insert key (merge key a b))
                (\key b -> Dict.insert key b)
                usedSoFar
                partiallyStrippedResponses
                Dict.empty


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


resolve : ApplicationType -> RawRequest value -> RequestsAndPending -> Result Error value
resolve appType request rawResponses =
    case request of
        RequestError error ->
            Err error

        Request _ ( _, lookupFn ) ->
            case lookupFn appType rawResponses of
                nextRequest ->
                    resolve appType nextRequest rawResponses

        ApiRoute _ value ->
            Ok value


resolveUrls : ApplicationType -> RawRequest value -> RequestsAndPending -> List Pages.StaticHttp.Request.Request
resolveUrls appType request rawResponses =
    resolveUrlsHelp appType rawResponses [] request


resolveUrlsHelp : ApplicationType -> RequestsAndPending -> List Pages.StaticHttp.Request.Request -> RawRequest value -> List Pages.StaticHttp.Request.Request
resolveUrlsHelp appType rawResponses soFar request =
    case request of
        RequestError error ->
            case error of
                MissingHttpResponse _ next ->
                    (soFar ++ next)
                        |> List.Extra.uniqueBy Pages.StaticHttp.Request.hash

                _ ->
                    soFar

        Request _ ( urlList, lookupFn ) ->
            resolveUrlsHelp appType
                rawResponses
                (soFar ++ urlList)
                (lookupFn appType rawResponses)

        ApiRoute _ _ ->
            soFar


cacheRequestResolution :
    ApplicationType
    -> RawRequest value
    -> RequestsAndPending
    -> Status value
cacheRequestResolution appType request rawResponses =
    cacheRequestResolutionHelp [] appType rawResponses request


type Status value
    = Incomplete (List Pages.StaticHttp.Request.Request)
    | HasPermanentError Error
    | Complete


cacheRequestResolutionHelp :
    List Pages.StaticHttp.Request.Request
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
                (lookupFn appType rawResponses)

        ApiRoute _ _ ->
            Complete
