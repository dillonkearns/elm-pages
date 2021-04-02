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
import TerminalText as Terminal
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
    | Unparsed String NoMetadata (ContentJson String)
      -- TODO need to have an UnparsedMarkup entry type so the right parser is applied
    | Parsed NoMetadata String (ContentJson (Result ParseError view))


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

        Parsed metadata body _ ->
            metadata


pagesWithErrors : ContentCache NoMetadata view -> List BuildError
pagesWithErrors cache =
    cache
        |> Result.map
            (\okCache ->
                List.filterMap
                    (\( path, value ) ->
                        case value of
                            Parsed metadata rawBody { body } ->
                                case body of
                                    Err parseError ->
                                        createBuildError path parseError |> Just

                                    _ ->
                                        Nothing

                            _ ->
                                Nothing
                    )
                    (Dict.toList okCache)
            )
        |> Result.withDefault []


init :
    Document NoMetadata view
    -> Content
    -> Maybe { contentJson : ContentJson String, initialUrl : { url | path : String } }
    -> ContentCache NoMetadata view
init document content maybeInitialPageContent =
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


createBuildError : List String -> String -> BuildError
createBuildError path decodeError =
    { title = "Metadata Decode Error"
    , message =
        [ Terminal.text "I ran into a problem when parsing the metadata for the page with this path: "
        , Terminal.text ("/" ++ String.join "/" path)
        , Terminal.text "\n\n"
        , Terminal.text decodeError
        ]
    , fatal = False
    }


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

                        Parsed _ _ _ ->
                            Task.succeed cacheResult

                Nothing ->
                    Task.succeed cacheResult


httpTask : Url -> Task Http.Error (ContentJson String)
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


type alias ContentJson body =
    { body : body
    , staticData : RequestsAndPending
    }


contentJsonDecoder : Decode.Decoder (ContentJson String)
contentJsonDecoder =
    Decode.map2 ContentJson
        (Decode.field "body" Decode.string)
        (Decode.field "staticData" RequestsAndPending.decoder)


update :
    ContentCache NoMetadata view
    -> (String -> Result ParseError view)
    -> { currentUrl : Url, baseUrl : Url }
    -> ContentJson String
    -> ContentCache NoMetadata view
update cacheResult renderer urls rawContent =
    case cacheResult of
        Ok cache ->
            Dict.update
                (pathForUrl urls)
                (\entry ->
                    case entry of
                        Just (Parsed metadata rawBody view) ->
                            entry

                        Just (Unparsed extension metadata content) ->
                            Parsed metadata
                                content.body
                                { body = renderer content.body
                                , staticData = content.staticData
                                }
                                |> Just

                        Just (NeedContent extension metadata) ->
                            Parsed metadata
                                rawContent.body
                                { body = renderer rawContent.body
                                , staticData = rawContent.staticData
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
                    NeedContent _ metadata ->
                        ( pagePath, metadata )

                    Unparsed _ metadata _ ->
                        ( pagePath, metadata )

                    Parsed metadata body _ ->
                        ( pagePath, metadata )
            )
