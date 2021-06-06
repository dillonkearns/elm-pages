module Pages.ContentCache exposing
    ( ContentCache
    , ContentJson
    , Entry(..)
    , Path
    , contentJsonDecoder
    , init
    , is404
    , lazyLoad
    , notFoundReason
    , pathForUrl
    )

import BuildError exposing (BuildError)
import Codec
import Dict exposing (Dict)
import Html exposing (Html)
import Http
import Json.Decode as Decode
import NotFoundReason
import Pages.Internal.String as String
import RequestsAndPending exposing (RequestsAndPending)
import Task exposing (Task)
import Url exposing (Url)


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias ContentCache =
    Dict Path Entry


type alias Errors =
    List ( Html Never, BuildError )


type alias ContentCacheInner =
    Dict Path Entry


type Entry
    = Parsed ContentJson


type alias ParseError =
    String


type alias Path =
    List String


init :
    Maybe ( { currentUrl : Url, baseUrl : Url }, ContentJson )
    -> ContentCache
init maybeInitialPageContent =
    Dict.fromList []
        |> (\dict ->
                case maybeInitialPageContent of
                    Nothing ->
                        dict

                    Just ( urls, contentJson ) ->
                        dict
                            |> Dict.insert (pathForUrl urls) (Parsed contentJson)
           )


{-| Get from the Cache... if it's not already parsed, it will
parse it before returning it and store the parsed version in the Cache
-}
lazyLoad :
    { currentUrl : Url, baseUrl : Url }
    -> ContentCache
    -> Task Http.Error ( Url, ContentJson, ContentCache )
lazyLoad urls cache =
    case Dict.get (pathForUrl urls) cache of
        Just (Parsed contentJson) ->
            Task.succeed
                ( urls.currentUrl
                , contentJson
                , cache
                )

        Nothing ->
            urls.currentUrl
                |> httpTask
                |> Task.map
                    (\downloadedContent ->
                        ( urls.currentUrl
                        , downloadedContent
                        , update
                            cache
                            urls
                            downloadedContent
                        )
                    )


httpTask : Url -> Task Http.Error ContentJson
httpTask url =
    Http.task
        { method = "GET"
        , headers = []
        , url =
            url.path
                |> String.chopForwardSlashes
                |> String.split "/"
                |> List.filter ((/=) "")
                |> (\l -> l ++ [ "content.json" ])
                |> String.join "/"
                |> String.append "/"
        , body = Http.emptyBody
        , resolver =
            Http.stringResolver
                (\response ->
                    case response of
                        Http.BadUrl_ url_ ->
                            Err (Http.BadUrl url_)

                        Http.Timeout_ ->
                            Err Http.Timeout

                        Http.NetworkError_ ->
                            Err Http.NetworkError

                        Http.BadStatus_ metadata _ ->
                            Err (Http.BadStatus metadata.statusCode)

                        Http.GoodStatus_ _ body ->
                            body
                                |> Decode.decodeString contentJsonDecoder
                                |> Result.mapError (\err -> Http.BadBody (Decode.errorToString err))
                )
        , timeout = Nothing
        }


type alias ContentJson =
    { staticData : RequestsAndPending
    , is404 : Bool
    , notFoundReason : Maybe NotFoundReason.Payload
    }


contentJsonDecoder : Decode.Decoder ContentJson
contentJsonDecoder =
    Decode.field "is404" Decode.bool
        |> Decode.andThen
            (\is404Value ->
                if is404Value then
                    Decode.map3 ContentJson
                        (Decode.succeed Dict.empty)
                        (Decode.succeed is404Value)
                        (Decode.at [ "staticData", "notFoundReason" ]
                            (Decode.string
                                |> Decode.andThen
                                    (\jsonString ->
                                        case
                                            Decode.decodeString
                                                (Codec.decoder NotFoundReason.codec
                                                    |> Decode.map Just
                                                )
                                                jsonString
                                        of
                                            Ok okValue ->
                                                Decode.succeed okValue

                                            Err error ->
                                                Decode.fail
                                                    (Decode.errorToString error)
                                    )
                            )
                        )

                else
                    Decode.map3 ContentJson
                        (Decode.field "staticData" RequestsAndPending.decoder)
                        (Decode.succeed is404Value)
                        (Decode.succeed Nothing)
            )
        |> Decode.map (Debug.log "contentJsonDecoder")


update :
    ContentCache
    -> { currentUrl : Url, baseUrl : Url }
    -> ContentJson
    -> ContentCache
update cache urls rawContent =
    Dict.update
        (pathForUrl urls)
        (\entry ->
            case entry of
                Just (Parsed _) ->
                    entry

                Nothing ->
                    { staticData = rawContent.staticData
                    , is404 = rawContent.is404
                    , notFoundReason = rawContent.notFoundReason
                    }
                        |> Parsed
                        |> Just
        )
        cache


pathForUrl : { currentUrl : Url, baseUrl : Url } -> Path
pathForUrl { currentUrl, baseUrl } =
    currentUrl.path
        |> String.dropLeft (String.length baseUrl.path)
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")


is404 :
    ContentCache
    -> { currentUrl : Url, baseUrl : Url }
    -> Bool
is404 dict urls =
    dict
        |> Dict.get (pathForUrl urls)
        |> Maybe.map
            (\entry ->
                case entry of
                    Parsed data ->
                        data.is404
            )
        |> Maybe.withDefault True


notFoundReason :
    ContentCache
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe NotFoundReason.Payload
notFoundReason dict urls =
    dict
        |> Dict.get (pathForUrl urls)
        |> Maybe.map
            (\entry ->
                case entry of
                    Parsed data ->
                        data.notFoundReason
            )
        |> Maybe.withDefault Nothing
