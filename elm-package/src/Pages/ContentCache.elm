module Pages.ContentCache exposing (ContentCache, Entry(..), Path, extractMetadata, init, lookup, pathForUrl, update, warmUpCache)

import Dict exposing (Dict)
import Html exposing (Html)
import Json.Decode
import Mark
import Mark.Error
import Result.Extra
import Url exposing (Url)


type alias Content =
    { markdown : List ( List String, { frontMatter : String, body : Maybe String } ), markup : List ( List String, String ) }


type alias ContentCache msg metadata view =
    Result (Html msg) (Dict Path (Entry metadata view))


type Entry metadata view
    = NeedContent metadata
    | Unparsed metadata String
      -- TODO need to have an UnparsedMarkup entry type so the right parser is applied
    | Parsed metadata (List view)


type alias Path =
    List String


extractMetadata : ContentCache msg metadata view -> List ( Path, metadata )
extractMetadata cacheResult =
    case cacheResult of
        Ok cache ->
            cache
                |> Dict.toList
                |> List.map (\( path, entry ) -> ( path, getMetadata entry ))

        Err _ ->
            -- TODO just return a list, don't handle result here
            []


getMetadata : Entry metadata view -> metadata
getMetadata entry =
    case entry of
        NeedContent metadata ->
            metadata

        Unparsed metadata _ ->
            metadata

        Parsed metadata _ ->
            metadata


init :
    Json.Decode.Decoder metadata
    -> Content
    ->
        (Dict String String
         -> List String
         -> List ( List String, metadata )
         ->
            Mark.Document
                { metadata : metadata
                , view : List view
                }
        )
    -> Dict String String
    -> ContentCache msg metadata view
init frontmatterParser content parser imageAssets =
    let
        parsedMarkdown =
            content.markdown
                |> List.map
                    (\(( path, details ) as full) ->
                        Tuple.mapSecond
                            (\{ frontMatter } ->
                                Json.Decode.decodeString frontmatterParser frontMatter
                                    |> Result.map NeedContent
                                    -- TODO include content when available here
                                    |> Result.mapError
                                        (\error ->
                                            Html.div []
                                                [ Html.h1 []
                                                    [ Html.text ("Error with page /" ++ String.join "/" path)
                                                    ]
                                                , Html.text
                                                    (Json.Decode.errorToString error)
                                                ]
                                        )
                            )
                            full
                    )

        parsedMarkup =
            parseMarkupMetadata parser imageAssets content.markup
    in
    [ parsedMarkdown
        |> combineTupleResults
    , parsedMarkup
    ]
        |> Result.Extra.combine
        |> Result.map List.concat
        |> Result.map Dict.fromList


parseMarkupMetadata :
    (Dict String String
     -> List String
     -> List ( List String, metadata )
     ->
        Mark.Document
            { metadata : metadata
            , view : List view
            }
    )
    -> Dict String String
    -> List ( List String, String )
    -> Result (Html msg) (List ( Path, Entry metadata view ))
parseMarkupMetadata parser imageAssets record =
    case
        record
            |> List.map
                (\( path, markup ) ->
                    ( path
                    , Mark.compile
                        (parser imageAssets
                            (routes record)
                            []
                        )
                        markup
                    , markup
                    )
                )
            |> combineResults
    of
        Ok pages ->
            Ok
                (pages
                 -- |> List.map
                 --     (Tuple.mapSecond (\thing -> Unparsed thing.metadata "thing.body"))
                )

        Err errors ->
            Err (renderErrors errors)


routes : List ( List String, String ) -> List String
routes record =
    record
        |> List.map Tuple.first
        |> List.map (String.join "/")
        |> List.map (\route -> "/" ++ route)


routesForCache : ContentCache msg metadata view -> List String
routesForCache viewmetadataContentCache =
    []


type alias Page metadata view =
    { metadata : metadata
    , view : List view
    }


renderErrors : ( List String, List Mark.Error.Error ) -> Html msg
renderErrors ( path, errors ) =
    Html.div []
        [ Html.text (path |> String.join "/")
        , errors
            |> List.map (Mark.Error.toHtml Mark.Error.Light)
            |> Html.div []
        ]


combineResults :
    List ( List String, Mark.Outcome (List Mark.Error.Error) (Mark.Partial (Page metadata view)) (Page metadata view), String )
    -> Result ( Path, List Mark.Error.Error ) (List ( Path, Entry metadata view ))
combineResults list =
    list
        |> List.map
            (\( path, outcome, rawMarkup ) ->
                case outcome of
                    Mark.Success parsedMarkup ->
                        Ok ( path, Unparsed parsedMarkup.metadata rawMarkup )

                    Mark.Almost partial ->
                        -- Err "Almost"
                        Err ( path, partial.errors )

                    Mark.Failure failures ->
                        Err ( path, failures )
            )
        |> Result.Extra.combine


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
lazyGet :
    ContentCache msg metadata view
    -> (String -> List view)
    -> Url
    -> ( ContentCache msg metadata view, Maybe ( metadata, List view ) )
lazyGet cacheResult renderer url =
    let
        path =
            pathForUrl url
    in
    case cacheResult of
        Ok cache ->
            Dict.get path cache
                |> (\maybeEntry ->
                        case maybeEntry of
                            Just (Parsed metadata view) ->
                                -- no parsing neeeded, just return the value
                                ( Ok cache, Just ( metadata, view ) )

                            Just (Unparsed metadata content) ->
                                let
                                    parsedEntry =
                                        Parsed metadata (renderer content)
                                in
                                -- update the cache and return the parsed value
                                ( cache
                                    |> Dict.insert path parsedEntry
                                    |> Ok
                                , Nothing
                                )

                            Just (NeedContent metadata) ->
                                -- Parsed metadata (renderer "")
                                --     |> Just
                                ( Ok cache, Nothing )

                            Nothing ->
                                -- TODO this should be Err, not Ok
                                ( Ok cache, Nothing )
                   )

        Err error ->
            -- TODO update this ever???
            -- Should this be something other than the raw HTML, or just concat the error HTML?
            ( Err error, Nothing )


warmUpCache :
    (Dict String String
     -> List String
     -> List ( List String, metadata )
     -> Mark.Document (Page metadata view)
    )
    -> Dict String String
    -> (String -> List view)
    -> Url
    -> ContentCache msg metadata view
    -> ContentCache msg metadata view
warmUpCache markupParser imageAssets renderer url cacheResult =
    let
        path =
            pathForUrl url
    in
    case cacheResult of
        Ok cache ->
            Dict.get path cache
                |> (\maybeEntry ->
                        case maybeEntry of
                            Just (Parsed metadata view) ->
                                -- no parsing neeeded, just return the value
                                Ok cache

                            Just (Unparsed metadata content) ->
                                let
                                    parsedMarkup =
                                        Mark.compile
                                            (markupParser imageAssets
                                                (Ok cache |> routesForCache)
                                                (extractMetadata (Ok cache))
                                            )
                                            content
                                in
                                -- update the cache and return the parsed value
                                case parsedMarkup of
                                    Mark.Success parsed ->
                                        -- TODO feels strange that the metadata could change here... make a way to
                                        -- only parse the metadata once
                                        cache
                                            |> Dict.insert path (Parsed metadata parsed.view)
                                            |> Ok

                                    Mark.Almost _ ->
                                        -- TODO update record to error
                                        Err (Html.text "Error parsing markup")

                                    Mark.Failure _ ->
                                        Err (Html.text "Error parsing markup")

                            Just (NeedContent metadata) ->
                                -- Parsed metadata (renderer "")
                                --     |> Just
                                Ok cache

                            Nothing ->
                                -- TODO this should be Err, not Ok
                                Ok cache
                   )

        Err error ->
            -- TODO update this ever???
            -- Should this be something other than the raw HTML, or just concat the error HTML?
            Err error


update :
    ContentCache msg metadata view
    -> (String -> view)
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

                        Just (Unparsed metadata content) ->
                            Parsed metadata (renderer content |> List.singleton)
                                |> Just

                        Just (NeedContent metadata) ->
                            Parsed metadata (renderer rawContent |> List.singleton)
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
