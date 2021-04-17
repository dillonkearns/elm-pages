module Pages.ContentCache exposing
    ( ContentCache
    , Entry(..)
    , Path
    , init
    , lazyLoad
    , lookup
    , lookupContentJson
    , lookupMetadata
    )

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Html exposing (Html)
import Http
import Json.Decode as Decode
import Pages.Internal.String as String
import Pages.PagePath as PagePath exposing (PagePath)
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
    = NeedContent
    | Parsed ContentJson


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
        Just entry ->
            case entry of
                NeedContent ->
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

                Parsed contentJson ->
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
    }


contentJsonDecoder : Decode.Decoder ContentJson
contentJsonDecoder =
    Decode.map ContentJson
        (Decode.field "staticData" RequestsAndPending.decoder)


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

                Just NeedContent ->
                    Parsed
                        { staticData = rawContent.staticData
                        }
                        |> Just

                Nothing ->
                    { staticData = rawContent.staticData }
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


lookup :
    ContentCache
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe ( PagePath, Entry )
lookup dict urls =
    let
        path =
            pathForUrl urls
    in
    dict
        |> Dict.get path
        |> Maybe.map
            (\entry ->
                ( PagePath.build path, entry )
            )


lookupMetadata :
    ContentCache
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe PagePath
lookupMetadata content urls =
    urls
        |> lookup content
        |> Maybe.map
            (\( pagePath, entry ) ->
                case entry of
                    NeedContent ->
                        pagePath

                    Parsed _ ->
                        pagePath
            )


lookupContentJson :
    ContentCache
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe RequestsAndPending
lookupContentJson content urls =
    urls
        |> lookup content
        |> Maybe.andThen
            (\( _, entry ) ->
                case entry of
                    NeedContent ->
                        Nothing

                    Parsed contentJson ->
                        Just contentJson.staticData
            )
