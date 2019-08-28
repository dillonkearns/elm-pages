module Pages.ContentCache exposing (ContentCache, Entry(..), Page, Path, extractMetadata, init, lazyLoad, lookup, pathForUrl, routesForCache, update)

import Dict exposing (Dict)
import Html exposing (Html)
import Http
import Json.Decode
import Mark
import Mark.Error
import Pages.Document
import Result.Extra
import Task exposing (Task)
import Url exposing (Url)
import Url.Builder


type alias Content =
    -- { markdown : List ( List String, { frontMatter : String, body : Maybe String } )
    -- , markup :
    --     List ( List String, { frontMatter : String, body : Maybe String } )
    -- }
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


type alias ContentCache msg metadata view =
    Result (Html msg) (Dict Path (Entry metadata view))


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


extractMetadata : ContentCacheInner metadata view -> List ( Path, metadata )
extractMetadata cache =
    cache
        |> Dict.toList
        |> List.map (\( path, entry ) -> ( path, getMetadata entry ))


getMetadata : Entry metadata view -> metadata
getMetadata entry =
    case entry of
        NeedContent extension metadata ->
            metadata

        Unparsed extension metadata _ ->
            metadata

        Parsed metadata _ ->
            metadata


init :
    Pages.Document.Document metadata view
    -> Content
    -> ContentCache msg metadata view
init document content =
    Pages.Document.parseMetadata document content
        |> List.map
            (Tuple.mapSecond
                (Result.map
                    (\{ metadata, extension } -> NeedContent extension metadata)
                )
            )
        |> combineTupleResults
        |> Result.mapError
            (\error ->
                Html.div []
                    [ Html.h2 []
                        [ Html.text "I found an error parsing some metadata" ]
                    , Html.text error
                    ]
            )
        |> Result.map Dict.fromList


routes : List ( List String, anything ) -> List String
routes record =
    record
        |> List.map Tuple.first
        |> List.map (String.join "/")
        |> List.map (\route -> "/" ++ route)


routesForCache : ContentCache msg metadata view -> List String
routesForCache cacheResult =
    case cacheResult of
        Ok cache ->
            cache
                |> Dict.toList
                |> routes

        Err _ ->
            []


type alias Page metadata view =
    { metadata : metadata
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
    -> Result error (List ( List String, success ))
combineTupleResults input =
    input
        |> List.map
            (\( path, result ) ->
                result
                    |> Result.map (\success -> ( path, success ))
            )
        |> Result.Extra.combine


{-| Get from the Cache... if it's not already parsed, it will
parse it before returning it and store the parsed version in the Cache
-}
lazyLoad :
    Pages.Document.Document metadata view
    -> Url
    -> ContentCache msg metadata view
    -> Task Http.Error (ContentCache msg metadata view)
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
                                                Pages.Document.parseContent extension thing document
                                            )
                                            url
                                            downloadedContent
                                    )

                        Unparsed extension metadata content ->
                            update cacheResult
                                (\thing ->
                                    Pages.Document.parseContent extension thing document
                                )
                                url
                                content
                                |> Task.succeed

                        Parsed _ _ ->
                            Task.succeed cacheResult

                Nothing ->
                    Task.succeed cacheResult



-- renderMarkup : String -> view
-- ren


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
    ContentCache msg metadata view
    -> (String -> Result ParseError view)
    -> Url
    -> String
    -> ContentCache msg metadata view
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
    ContentCache msg metadata view
    -> Url
    -> Maybe (Entry metadata view)
lookup content url =
    case content of
        Ok dict ->
            Dict.get (pathForUrl url) dict

        Err _ ->
            Nothing


dropTrailingSlash path =
    if path |> String.endsWith "/" then
        String.dropRight 1 path

    else
        path
