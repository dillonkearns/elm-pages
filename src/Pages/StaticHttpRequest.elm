module Pages.StaticHttpRequest exposing (Error(..), MockResolver, RawRequest(..), Status(..), cacheRequestResolution, mockResolve, toBuildError)

import BuildError exposing (BuildError)
import Dict
import Json.Encode
import Pages.StaticHttp.Request
import RequestsAndPending exposing (RequestsAndPending)
import TerminalText as Terminal


type alias MockResolver =
    Pages.StaticHttp.Request.Request
    -> Maybe RequestsAndPending.Response


type RawRequest error value
    = Request (List Pages.StaticHttp.Request.Request) (Maybe MockResolver -> RequestsAndPending -> RawRequest error value)
    | ApiRoute (Result error value)


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
                [ Terminal.text <| "I ran into a call to `BackendTask.fail` with message: " ++ decodeErrorMessage
                ]
            , path = path
            , fatal = True
            }


mockResolve : RawRequest error value -> MockResolver -> Result error value
mockResolve request mockResolver =
    case request of
        Request _ lookupFn ->
            case lookupFn (Just mockResolver) (Json.Encode.object []) of
                nextRequest ->
                    mockResolve nextRequest mockResolver

        ApiRoute value ->
            value


cacheRequestResolution :
    RawRequest error value
    -> RequestsAndPending
    -> Status error value
cacheRequestResolution request rawResponses =
    case request of
        Request urlList lookupFn ->
            if List.isEmpty urlList then
                cacheRequestResolutionHelp urlList rawResponses (lookupFn Nothing rawResponses)

            else
                Incomplete urlList (Request [] lookupFn)

        ApiRoute value ->
            Complete value


type Status error value
    = Incomplete (List Pages.StaticHttp.Request.Request) (RawRequest error value)
    | HasPermanentError Error
    | Complete (Result error value)


cacheRequestResolutionHelp :
    List Pages.StaticHttp.Request.Request
    -> RequestsAndPending
    -> RawRequest error value
    -> Status error value
cacheRequestResolutionHelp foundUrls rawResponses request =
    case request of
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
