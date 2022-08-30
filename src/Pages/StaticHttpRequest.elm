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


type RawRequest error value
    = Request (List Pages.StaticHttp.Request.Request) (Maybe MockResolver -> RequestsAndPending -> RawRequest error value)
    | RequestError (Error error)
    | ApiRoute value


type
    -- TODO rename Error -> InternalError
    Error error
    = MissingHttpResponse String (List Pages.StaticHttp.Request.Request)
    | DecoderError String
      -- TODO move UserCalledStaticHttpFail to be handled through UserError
    | UserCalledStaticHttpFail String
    | UserError error


toBuildError : String -> Error error -> BuildError
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

        UserError _ ->
            { title = "TODO"
            , message =
                [ Terminal.text <| "Unexpected case"
                ]
            , path = path
            , fatal = True
            }


resolve : RawRequest error value -> RequestsAndPending -> Result (Error error) value
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


mockResolve : RawRequest error value -> MockResolver -> Result (Error error) value
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


resolveUrls : RawRequest error value -> RequestsAndPending -> List Pages.StaticHttp.Request.Request
resolveUrls request rawResponses =
    resolveUrlsHelp rawResponses [] request


resolveUrlsHelp : RequestsAndPending -> List Pages.StaticHttp.Request.Request -> RawRequest error value -> List Pages.StaticHttp.Request.Request
resolveUrlsHelp rawResponses soFar request =
    case request of
        RequestError error ->
            case error of
                MissingHttpResponse _ next ->
                    (soFar ++ next)
                        |> List.Extra.uniqueBy Pages.StaticHttp.Request.hash

                _ ->
                    soFar

        Request urlList lookupFn ->
            resolveUrlsHelp
                rawResponses
                (soFar ++ urlList)
                (lookupFn Nothing rawResponses)

        ApiRoute _ ->
            soFar


cacheRequestResolution :
    RawRequest error value
    -> RequestsAndPending
    -> Status error value
cacheRequestResolution request rawResponses =
    cacheRequestResolutionHelp [] rawResponses request


type Status error value
    = Incomplete (List Pages.StaticHttp.Request.Request)
    | HasPermanentError (Error error)
    | Complete


cacheRequestResolutionHelp :
    List Pages.StaticHttp.Request.Request
    -> RequestsAndPending
    -> RawRequest error value
    -> Status error value
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

                UserError userError ->
                    HasPermanentError (UserError userError)

        Request urlList lookupFn ->
            cacheRequestResolutionHelp urlList
                rawResponses
                (lookupFn Nothing rawResponses)

        ApiRoute _ ->
            Complete
