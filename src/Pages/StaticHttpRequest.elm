module Pages.StaticHttpRequest exposing (Error(..), MockResolver, RawRequest(..), Status(..), cacheRequestResolution, mockResolve, toBuildError)

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
            cacheRequestResolutionHelp [] rawResponses request

        Request urlList lookupFn ->
            if List.isEmpty urlList then
                cacheRequestResolutionHelp urlList rawResponses (lookupFn Nothing rawResponses)

            else
                Incomplete urlList (Request [] lookupFn)

        ApiRoute value ->
            Complete value


type Status value
    = Incomplete (List Pages.StaticHttp.Request.Request) (RawRequest value)
    | HasPermanentError Error
    | Complete value


cacheRequestResolutionHelp :
    List Pages.StaticHttp.Request.Request
    -> RequestsAndPending
    -> RawRequest value
    -> Status value
cacheRequestResolutionHelp foundUrls rawResponses request =
    case request of
        RequestError error ->
            case error of
                DecoderError _ ->
                    HasPermanentError error

                UserCalledStaticHttpFail _ ->
                    HasPermanentError error

        Request urlList lookupFn ->
            if (urlList ++ foundUrls) |> List.isEmpty then
                cacheRequestResolutionHelp
                    []
                    rawResponses
                    (lookupFn Nothing rawResponses)

            else
                Incomplete (urlList ++ foundUrls)
                    (Request [] lookupFn)

        ApiRoute value ->
            Complete value
