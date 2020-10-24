module Pages.ContentCache exposing
    ( ContentCache
    , Entry(..)
    , Page
    , Path
    , errorView
    , extractMetadata
    , init
    , lazyLoad
    , lookup
    , lookupMetadata
    , pagesWithErrors
    , parseContent
    , pathForUrl
    , routesForCache
    , update
    )

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Json.Decode as Decode
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
    = NeedContent String metadata
    | Unparsed String metadata (ContentJson String)
      -- TODO need to have an UnparsedMarkup entry type so the right parser is applied
    | Parsed metadata String (ContentJson (Result ParseError view))


type alias ParseError =
    String


type alias Path =
    List String


extractMetadata : pathKey -> ContentCacheInner metadata view -> List ( PagePath pathKey, metadata )
extractMetadata pathKey cache =
    cache
        |> Dict.toList
        |> List.map (\( path, entry ) -> ( PagePath.build pathKey path, getMetadata entry ))


getMetadata : Entry metadata view -> metadata
getMetadata entry =
    case entry of
        NeedContent extension metadata ->
            metadata

        Unparsed extension metadata _ ->
            metadata

        Parsed metadata body _ ->
            metadata


pagesWithErrors : ContentCache metadata view -> List BuildError
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
    Document metadata view
    -> Content
    -> Maybe { contentJson : ContentJson String, initialUrl : { url | path : String } }
    -> ContentCache metadata view
init document content maybeInitialPageContent =
    content
        |> parseMetadata maybeInitialPageContent document
        |> List.map
            (\tuple ->
                tuple
                    |> Tuple.first
                    |> createErrors
                    |> Result.mapError
                    |> (\f -> Tuple.mapSecond f tuple)
            )
        |> combineTupleResults
        |> Result.map Dict.fromList


createErrors path decodeError =
    ( createHtmlError path decodeError, createBuildError path decodeError )


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


parseMetadata :
    Maybe { contentJson : ContentJson String, initialUrl : { url | path : String } }
    -> Document metadata view
    -> List ( List String, { extension : String, frontMatter : String, body : Maybe String } )
    -> List ( List String, Result String (Entry metadata view) )
parseMetadata maybeInitialPageContent document content =
    List.map
        (\( path, { frontMatter, extension, body } ) ->
            let
                maybeDocumentEntry =
                    Document.get extension document
            in
            case maybeDocumentEntry of
                Just documentEntry ->
                    frontMatter
                        |> documentEntry.frontmatterParser
                        |> Result.map
                            (\metadata ->
                                let
                                    renderer value =
                                        parseContent extension value document
                                in
                                case maybeInitialPageContent of
                                    Just { contentJson, initialUrl } ->
                                        if normalizePath initialUrl.path == (String.join "/" path |> normalizePath) then
                                            Parsed metadata
                                                contentJson.body
                                                { body = renderer contentJson.body
                                                , staticData = contentJson.staticData
                                                }

                                        else
                                            NeedContent extension metadata

                                    Nothing ->
                                        case body of
                                            -- the CLI generated content includes the body
                                            -- the generated content for the dev and production browser mode does not
                                            -- so we can ignore the StaticData here
                                            -- TODO use types to make this more semantic
                                            Just bodyFromCli ->
                                                Parsed metadata
                                                    bodyFromCli
                                                    { body = renderer bodyFromCli
                                                    , staticData = Dict.empty
                                                    }

                                            Nothing ->
                                                NeedContent extension metadata
                            )
                        |> Tuple.pair path

                Nothing ->
                    Err ("Could not find extension '" ++ extension ++ "'")
                        |> Tuple.pair path
        )
        content


normalizePath : String -> String
normalizePath pathString =
    let
        hasPrefix =
            String.startsWith "/" pathString

        hasSuffix =
            String.endsWith "/" pathString
    in
    if pathString == "" then
        pathString

    else
        String.concat
            [ if hasPrefix then
                String.dropLeft 1 pathString

              else
                pathString
            , if hasSuffix then
                ""

              else
                "/"
            ]


parseContent :
    String
    -> String
    -> Document metadata view
    -> Result String view
parseContent extension body document =
    let
        maybeDocumentEntry =
            Document.get extension document
    in
    case maybeDocumentEntry of
        Just documentEntry ->
            documentEntry.contentParser body

        Nothing ->
            Err ("Could not find extension '" ++ extension ++ "'")


errorView : Errors -> Html msg
errorView errors =
    errors
        --        |> Dict.toList
        |> List.map Tuple.first
        |> List.map (Html.map never)
        |> Html.div
            [ Attr.style "padding" "20px 100px"
            ]


createHtmlError : List String -> String -> Html msg
createHtmlError path error =
    Html.div []
        [ Html.h2 []
            [ Html.text (String.join "/" path)
            ]
        , Html.p [] [ Html.text "I couldn't parse the frontmatter in this page. I ran into this error with your JSON decoder:" ]
        , Html.pre [] [ Html.text error ]
        ]


routes : List ( List String, anything ) -> List String
routes record =
    record
        |> List.map Tuple.first
        |> List.map (String.join "/")


routesForCache : ContentCache metadata view -> List String
routesForCache cacheResult =
    case cacheResult of
        Ok cache ->
            cache
                |> Dict.toList
                |> routes

        Err _ ->
            []


type alias Page metadata view pathKey =
    { metadata : metadata
    , path : PagePath pathKey
    , view : view
    }


combineTupleResults :
    List ( List String, Result error success )
    -> Result (List error) (List ( List String, success ))
combineTupleResults input =
    input
        |> List.map
            (\( path, result ) ->
                result
                    |> Result.map (\success -> ( path, success ))
            )
        |> combine


combine : List (Result error ( List String, success )) -> Result (List error) (List ( List String, success ))
combine list =
    list
        |> List.foldr resultFolder (Ok [])


resultFolder : Result error a -> Result (List error) (List a) -> Result (List error) (List a)
resultFolder current soFarResult =
    case soFarResult of
        Ok soFarOk ->
            case current of
                Ok currentOk ->
                    currentOk
                        :: soFarOk
                        |> Ok

                Err error ->
                    Err [ error ]

        Err soFarErr ->
            case current of
                Ok currentOk ->
                    Err soFarErr

                Err error ->
                    error
                        :: soFarErr
                        |> Err


{-| Get from the Cache... if it's not already parsed, it will
parse it before returning it and store the parsed version in the Cache
-}
lazyLoad :
    Document metadata view
    -> { currentUrl : Url, baseUrl : Url }
    -> ContentCache metadata view
    -> Task Http.Error (ContentCache metadata view)
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
    ContentCache metadata view
    -> (String -> Result ParseError view)
    -> { currentUrl : Url, baseUrl : Url }
    -> ContentJson String
    -> ContentCache metadata view
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
    -> ContentCache metadata view
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe ( PagePath pathKey, Entry metadata view )
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
    -> ContentCache metadata view
    -> { currentUrl : Url, baseUrl : Url }
    -> Maybe ( PagePath pathKey, metadata )
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
