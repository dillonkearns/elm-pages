module Pages.ContentCache exposing
    ( ContentCache
    , Entry(..)
    , Path
    , extractMetadata
    , init
    , lazyLoad
    , lookup
    , lookupMetadata
    , pagesWithErrors
    , routesForCache
    )

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Html exposing (Html)
import Http
import Json.Decode as Decode
import NoMetadata exposing (NoMetadata, NoView(..))
import Pages.Document as Document exposing (Document)
import Pages.Internal.String as String
import Pages.PagePath as PagePath exposing (PagePath)
import RequestsAndPending exposing (RequestsAndPending)
import Task exposing (Task)
import Url exposing (Url)


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias ContentCache metadata view =
    Result Errors (Dict Path (Entry metadata view))


type alias Errors =
    List ( Html Never, BuildError )


type alias ContentCacheInner metadata view =
    Dict Path (Entry metadata view)


type Entry metadata view
    = NeedContent String NoMetadata
    | Unparsed String NoMetadata ContentJson
      -- TODO need to have an UnparsedMarkup entry type so the right parser is applied
    | Parsed NoMetadata ContentJson


type alias ParseError =
    String


type alias Path =
    List String


extractMetadata : pathKey -> ContentCacheInner NoMetadata view -> List ( PagePath pathKey, NoMetadata )
extractMetadata pathKey cache =
    cache
        |> Dict.toList
        |> List.map (\( path, entry ) -> ( PagePath.build pathKey path, getMetadata entry ))


getMetadata : Entry NoMetadata view -> NoMetadata
getMetadata entry =
    case entry of
        NeedContent extension metadata ->
            metadata

        Unparsed extension metadata _ ->
            metadata

        Parsed metadata _ ->
            metadata


pagesWithErrors : ContentCache NoMetadata view -> List BuildError
pagesWithErrors cache =
    []


init :
    Document NoMetadata view
    -> Content
    -> Maybe { contentJson : ContentJson, initialUrl : { url | path : String } }
    -> ContentCache NoMetadata view
init _ _ maybeInitialPageContent =
    Ok <|
        Dict.fromList
            [ ( [], NeedContent "" NoMetadata.NoMetadata )
            , ( [ "showcase" ], NeedContent "" NoMetadata.NoMetadata )
            , ( [ "blog" ], NeedContent "" NoMetadata.NoMetadata )

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


parseContent :
    String
    -> String
    -> Document NoMetadata NoView
    -> Result String NoView
parseContent extension body document =
    let
        maybeDocumentEntry =
            Document.get extension document
    in
    case maybeDocumentEntry of
        Just documentEntry ->
            documentEntry.contentParser body

        Nothing ->
            Ok NoView



--Err ("Could not find extension '" ++ extension ++ "'")


routes : List ( List String, anything ) -> List String
routes record =
    record
        |> List.map Tuple.first
        |> List.map (String.join "/")


routesForCache : ContentCache NoMetadata view -> List String
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
    Document NoMetadata NoView
    -> { currentUrl : Url, baseUrl : Url }
    -> ContentCache NoMetadata NoView
    -> Task Http.Error (ContentCache NoMetadata NoView)
lazyLoad document urls cacheResult =
    case cacheResult of
        Err _ ->
            Task.succeed cacheResult

        Ok cache ->
            case Dict.get (pathForUrl urls) cache of
                Just entry ->
                    case entry of
                        NeedContent extension _ ->
                            urls.currentUrl
                                |> httpTask
                                |> Task.map
                                    (\downloadedContent ->
                                        update
                                            cacheResult
                                            (\value ->
                                                parseContent extension value document
                                            )
                                            urls
                                            downloadedContent
                                    )

                        Unparsed extension metadata content ->
                            content
                                |> update
                                    cacheResult
                                    (\thing ->
                                        parseContent extension thing document
                                    )
                                    urls
                                |> Task.succeed

                        Parsed _ _ ->
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

                        Http.BadStatus_ metadata body ->
                            Err (Http.BadStatus metadata.statusCode)

                        Http.GoodStatus_ metadata body ->
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
    ContentCache NoMetadata view
    -> (String -> Result ParseError view)
    -> { currentUrl : Url, baseUrl : Url }
    -> ContentJson
    -> ContentCache NoMetadata view
update cacheResult _ urls rawContent =
    case cacheResult of
        Ok cache ->
            Dict.update
                (pathForUrl urls)
                (\entry ->
                    case entry of
                        Just (Parsed _ _) ->
                            entry

                        Just (Unparsed _ _ content) ->
                            Parsed NoMetadata
                                { staticData = content.staticData
                                }
                                |> Just

                        Just (NeedContent _ _) ->
                            Parsed NoMetadata
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
    -> ContentCache NoMetadata NoView
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe ( PagePath pathKey, Entry NoMetadata NoView )
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
    -> ContentCache NoMetadata NoView
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe ( PagePath pathKey, NoMetadata )
lookupMetadata pathKey content urls =
    urls
        |> lookup pathKey content
        |> Maybe.map
            (\( pagePath, entry ) ->
                case entry of
                    NeedContent _ _ ->
                        ( pagePath, NoMetadata )

                    Unparsed _ _ _ ->
                        ( pagePath, NoMetadata )

                    Parsed _ _ ->
                        ( pagePath, NoMetadata )
            )
