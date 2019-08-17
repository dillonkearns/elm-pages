module Pages.ContentCache exposing (ContentCache, Entry(..), Path, extractMetadata, init, lookup, pathForUrl, update)

import Dict exposing (Dict)
import Html exposing (Html)
import Json.Decode
import Result.Extra
import Url exposing (Url)


type alias Content =
    { markdown : List ( List String, { frontMatter : String, body : Maybe String } ), markup : List ( List String, String ) }


type alias ContentCache msg metadata view =
    Result (Html msg) (Dict Path (Entry metadata view))


type Entry metadata view
    = NeedContent metadata
    | Unparsed metadata String
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
    -> ContentCache msg metadata view
init frontmatterParser content =
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
    in
    parsedMarkdown
        |> combineTupleResults
        |> Result.map Dict.fromList


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
