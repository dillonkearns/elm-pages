module Pages.StaticHttpRequest exposing (Error(..), MockResolver, RawRequest(..), Status(..), cacheRequestResolution, mockResolve, resolve, resolveUrls, toBuildError)

import BuildError exposing (BuildError)
import Dict
import List.Extra
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


resolveUrls : RawRequest value -> RequestsAndPending -> List Pages.StaticHttp.Request.Request
resolveUrls request rawResponses =
    resolveUrlsHelp rawResponses [] request


resolveUrlsHelp : RequestsAndPending -> List Pages.StaticHttp.Request.Request -> RawRequest value -> List Pages.StaticHttp.Request.Request
resolveUrlsHelp rawResponses soFar request =
    case request of
        RequestError error ->
            case error of
                MissingHttpResponse _ next ->
                    --soFar ++ next
                    next

                --|> List.Extra.uniqueBy Pages.StaticHttp.Request.hash
                _ ->
                    --soFar
                    []

        Request urlList lookupFn ->
            resolveUrlsHelp
                rawResponses
                --(soFar ++ urlList)
                urlList
                (lookupFn Nothing rawResponses)

        ApiRoute _ ->
            --soFar
            []


cacheRequestResolution :
    RawRequest value
    -> RequestsAndPending
    -> Status value
cacheRequestResolution request rawResponses =
    cacheRequestResolutionHelp [] rawResponses request request


type Status value
    = Incomplete (List Pages.StaticHttp.Request.Request) (RawRequest value)
    | HasPermanentError Error (RawRequest value)
    | Complete


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
                MissingHttpResponse _ _ ->
                    -- TODO do I need to pass through continuation URLs here? -- Incomplete (urlList ++ foundUrls)
                    Incomplete foundUrls parentRequest

                DecoderError _ ->
                    HasPermanentError error parentRequest

                UserCalledStaticHttpFail _ ->
                    HasPermanentError error parentRequest

        Request urlList lookupFn ->
            cacheRequestResolutionHelp urlList
                rawResponses
                request
                (lookupFn Nothing rawResponses)

        ApiRoute _ ->
            Complete
