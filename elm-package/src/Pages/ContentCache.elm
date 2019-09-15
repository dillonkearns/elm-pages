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
    , pathForUrl
    , routesForCache
    , update
    )

import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes as Attr
import Http
import Json.Decode
import Mark
import Mark.Error
import Pages.Document as Document exposing (Document)
import Pages.PagePath as PagePath exposing (PagePath)
import Result.Extra
import Task exposing (Task)
import Url exposing (Url)
import Url.Builder


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias ContentCache metadata view =
    Result Errors (Dict Path (Entry metadata view))


type alias Errors =
    Dict Path String


type alias ContentCacheInner metadata view =
    Dict Path (Entry metadata view)


type Entry metadata view
    = NeedContent String metadata
    | Unparsed String metadata String
      -- TODO need to have an UnparsedMarkup entry type so the right parser is applied
    | Parsed metadata (Result ParseError view)


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

        Parsed metadata _ ->
            metadata


pagesWithErrors : ContentCache metadata view -> Maybe (Dict (List String) String)
pagesWithErrors cache =
    cache
        |> Result.map
            (\okCache ->
                okCache
                    |> Dict.toList
                    |> List.filterMap
                        (\( path, value ) ->
                            case value of
                                Parsed metadata (Err parseError) ->
                                    Just ( path, parseError )

                                _ ->
                                    Nothing
                        )
            )
        |> Result.map
            (\errors ->
                case errors of
                    [] ->
                        Nothing

                    _ ->
                        errors
                            |> Dict.fromList
                            |> Just
            )
        |> Result.withDefault Nothing


init :
    Document metadata view
    -> Content
    -> ContentCache metadata view
init document content =
    parseMetadata document content
        |> List.map
            (\tuple ->
                Tuple.mapSecond
                    (\result ->
                        result
                            |> Result.mapError (\error -> ( Tuple.first tuple, error ))
                    )
                    tuple
            )
        |> combineTupleResults
        |> Result.mapError Dict.fromList
        |> Result.map Dict.fromList


parseMetadata :
    Document metadata view
    -> List ( List String, { extension : String, frontMatter : String, body : Maybe String } )
    -> List ( List String, Result String (Entry metadata view) )
parseMetadata document content =
    content
        |> List.map
            (Tuple.mapSecond
                (\{ frontMatter, extension, body } ->
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
                                        case body of
                                            Just presentBody ->
                                                Parsed metadata
                                                    (parseContent extension presentBody document)

                                            Nothing ->
                                                NeedContent extension metadata
                                    )

                        Nothing ->
                            Err ("Could not find extension '" ++ extension ++ "'")
                )
            )


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
        |> Dict.toList
        |> List.map errorEntryView
        |> Html.div
            [ Attr.style "padding" "20px 100px"
            ]


errorEntryView : ( Path, String ) -> Html msg
errorEntryView ( path, error ) =
    Html.div []
        [ Html.h2 []
            [ Html.text ("/" ++ (path |> String.join "/"))
            ]
        , Html.p [] [ Html.text "I couldn't parse the frontmatter in this page. I ran into this error with your JSON decoder:" ]
        , Html.pre [] [ Html.text error ]
        ]


routes : List ( List String, anything ) -> List String
routes record =
    record
        |> List.map Tuple.first
        |> List.map (String.join "/")
        |> List.map (\route -> "/" ++ route)


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


renderErrors : ( List String, List Mark.Error.Error ) -> Html msg
renderErrors ( path, errors ) =
    Html.div []
        [ Html.text (path |> String.join "/")
        , errors
            |> List.map (Mark.Error.toHtml Mark.Error.Light)
            |> Html.div []
        ]


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
    -> Url
    -> ContentCache metadata view
    -> Task Http.Error (ContentCache metadata view)
lazyLoad document url cacheResult =
    case cacheResult of
        Err _ ->
            Task.succeed cacheResult

        Ok cache ->
            case Dict.get (pathForUrl url) cache of
                Just entry ->
                    case entry of
                        NeedContent extension _ ->
                            httpTask url
                                |> Task.map
                                    (\downloadedContent ->
                                        update cacheResult
                                            (\thing ->
                                                parseContent extension thing document
                                            )
                                            url
                                            downloadedContent
                                    )

                        Unparsed extension metadata content ->
                            update cacheResult
                                (\thing ->
                                    parseContent extension thing document
                                )
                                url
                                content
                                |> Task.succeed

                        Parsed _ _ ->
                            Task.succeed cacheResult

                Nothing ->
                    Task.succeed cacheResult


httpTask url =
    Http.task
        { method = "GET"
        , headers = []
        , url =
            Url.Builder.absolute
                ((url.path |> String.split "/" |> List.filter (not << String.isEmpty))
                    ++ [ "content.txt"
                       ]
                )
                []
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
                            Ok body
                )
        , timeout = Nothing
        }


update :
    ContentCache metadata view
    -> (String -> Result ParseError view)
    -> Url
    -> String
    -> ContentCache metadata view
update cacheResult renderer url rawContent =
    case cacheResult of
        Ok cache ->
            Dict.update (pathForUrl url)
                (\entry ->
                    case entry of
                        Just (Parsed metadata view) ->
                            entry

                        Just (Unparsed extension metadata content) ->
                            Parsed metadata (renderer content)
                                |> Just

                        Just (NeedContent extension metadata) ->
                            Parsed metadata (renderer rawContent)
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


pathForUrl : Url -> Path
pathForUrl url =
    url.path
        |> dropTrailingSlash
        |> String.split "/"
        |> List.drop 1


lookup :
    pathKey
    -> ContentCache metadata view
    -> Url
    -> Maybe ( PagePath pathKey, Entry metadata view )
lookup pathKey content url =
    case content of
        Ok dict ->
            let
                path =
                    pathForUrl url
            in
            Dict.get path dict
                |> Maybe.map
                    (\entry ->
                        ( PagePath.build pathKey path, entry )
                    )

        Err _ ->
            Nothing


lookupMetadata :
    ContentCache metadata view
    -> Url
    -> Maybe metadata
lookupMetadata content url =
    lookup () content url
        |> Maybe.map
            (\( pagePath, entry ) ->
                case entry of
                    NeedContent _ metadata ->
                        metadata

                    Unparsed _ metadata _ ->
                        metadata

                    Parsed metadata _ ->
                        metadata
            )


dropTrailingSlash path =
    if path |> String.endsWith "/" then
        String.dropRight 1 path

    else
        path
