module Pages.ContentCache exposing
    ( ContentCache
    , Entry(..)
    , Path
    , init
    , lazyLoad
    , lookup
    , lookupMetadata
    , routesForCache
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
    Result Errors (Dict Path Entry)


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
    Maybe { contentJson : ContentJson, initialUrl : { url | path : String } }
    -> ContentCache
init maybeInitialPageContent =
    Ok <|
        Dict.fromList
            [ ( [], NeedContent )
            , ( [ "showcase" ], NeedContent )
            , ( [ "blog" ], NeedContent )
            , ( [ "page" ], NeedContent )

            --, ( [], NeedContent "/showcase" NoMetadata.NoMetadata )
            ]



--content
--    --[]
--    |> parseMetadata maybeInitialPageContent document
--    |> List.map
--        (\tuple ->
--            tuple
--                |> Tuple.first
--                |> createErrors
--                |> Result.mapError
--                |> (\f -> Tuple.mapSecond f tuple)
--        )
--    |> combineTupleResults
--    |> Result.map Dict.fromList


routes : List ( List String, anything ) -> List String
routes record =
    record
        |> List.map Tuple.first
        |> List.map (String.join "/")


routesForCache : ContentCache -> List String
routesForCache cacheResult =
    case cacheResult of
        Ok cache ->
            cache
                |> Dict.toList
                |> routes

        Err _ ->
            []


{-| Get from the Cache... if it's not already parsed, it will
parse it before returning it and store the parsed version in the Cache
-}
lazyLoad :
    { currentUrl : Url, baseUrl : Url }
    -> ContentCache
    -> Task Http.Error ContentCache
lazyLoad urls cacheResult =
    case cacheResult of
        Err _ ->
            Task.succeed cacheResult

        Ok cache ->
            case Dict.get (pathForUrl urls) cache of
                Just entry ->
                    case entry of
                        NeedContent ->
                            urls.currentUrl
                                |> httpTask
                                |> Task.map
                                    (\downloadedContent ->
                                        update
                                            cacheResult
                                            urls
                                            downloadedContent
                                    )

                        Parsed _ ->
                            Task.succeed cacheResult

                Nothing ->
                    Task.succeed cacheResult


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
update cacheResult urls rawContent =
    case cacheResult of
        Ok cache ->
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
                            -- TODO this should never happen
                            Nothing
                )
                cache
                |> Ok

        Err error ->
            -- TODO update this ever???
            -- Should this be something other than the raw HTML, or just concat the error HTML?
            Err error


pathForUrl : { currentUrl : Url, baseUrl : Url } -> Path
pathForUrl { currentUrl, baseUrl } =
    currentUrl.path
        |> String.dropLeft (String.length baseUrl.path)
        |> String.chopForwardSlashes
        |> String.split "/"
        |> List.filter ((/=) "")


lookup :
    pathKey
    -> ContentCache
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe ( PagePath pathKey, Entry )
lookup pathKey content urls =
    case content of
        Ok dict ->
            let
                path =
                    pathForUrl urls
            in
            dict
                |> Dict.get path
                |> Maybe.map
                    (\entry ->
                        ( PagePath.build pathKey path, entry )
                    )

        Err _ ->
            Nothing


lookupMetadata :
    pathKey
    -> ContentCache
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe (PagePath pathKey)
lookupMetadata pathKey content urls =
    urls
        |> lookup pathKey content
        |> Maybe.map
            (\( pagePath, entry ) ->
                case entry of
                    NeedContent ->
                        pagePath

                    Parsed _ ->
                        pagePath
            )
