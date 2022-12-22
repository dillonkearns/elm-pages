module Pages.StaticHttpRequest exposing (Error(..), MockResolver, RawRequest(..), Status(..), cacheRequestResolution, mockResolve, resolve, toBuildError)

import BuildError exposing (BuildError)
import Dict
import Pages.StaticHttp.Request
import RequestsAndPending exposing (RequestsAndPending)
import TerminalText as Terminal


type alias MockResolver =
    Pages.StaticHttp.Request.Request
    -> Maybe RequestsAndPending.Response


type RawRequest value
    = Request (List Pages.StaticHttp.Request.Request) (Maybe MockResolver -> RequestsAndPending -> RawRequest value)
    | RequestError Error
    | ApiRoute value


type Error
    = DecoderError String
    | UserCalledStaticHttpFail String


toBuildError : String -> Error -> BuildError
toBuildError path error =
    case error of
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

        Request _ lookupFn ->
            case lookupFn Nothing rawResponses of
                nextRequest ->
                    resolve nextRequest rawResponses

        ApiRoute value ->
            Ok value


mockResolve : RawRequest value -> MockResolver -> Result Error value
mockResolve request mockResolver =
    case request of
        RequestError error ->
            Err error

        Request _ lookupFn ->
            case lookupFn (Just mockResolver) Dict.empty of
                nextRequest ->
                    mockResolve nextRequest mockResolver

        ApiRoute value ->
            Ok value


cacheRequestResolution :
    RawRequest value
    -> RequestsAndPending
    -> Status value
cacheRequestResolution request rawResponses =
    case request of
        RequestError _ ->
            cacheRequestResolutionHelp [] rawResponses request request

        Request urlList lookupFn ->
            if List.isEmpty urlList then
                cacheRequestResolutionHelp urlList rawResponses request (lookupFn Nothing rawResponses)

            else
                Incomplete urlList (Request [] lookupFn)

        ApiRoute value ->
            Complete value


type Status value
    = Incomplete (List Pages.StaticHttp.Request.Request) (RawRequest value)
    | HasPermanentError Error (RawRequest value)
    | Complete value


cacheRequestResolutionHelp :
    List Pages.StaticHttp.Request.Request
    -> RequestsAndPending
    -> RawRequest value
    -> RawRequest value
    -> Status value
cacheRequestResolutionHelp foundUrls rawResponses parentRequest request =
    case request of
        RequestError error ->
            case error of
                DecoderError _ ->
                    HasPermanentError error parentRequest

                UserCalledStaticHttpFail _ ->
                    HasPermanentError error parentRequest

        Request urlList lookupFn ->
            if (urlList ++ foundUrls) |> List.isEmpty then
                cacheRequestResolutionHelp
                    []
                    rawResponses
                    request
                    (lookupFn Nothing rawResponses)

            else
                Incomplete (urlList ++ foundUrls)
                    (Request [] lookupFn)

        ApiRoute value ->
            Complete value
