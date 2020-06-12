module Pages.Internal.Platform.StaticResponses exposing (..)

import BuildError exposing (BuildError)
import Dict exposing (Dict)
import Dict.Extra
import Pages.Internal.ApplicationType as ApplicationType
import Pages.Internal.Platform.Mode as Mode exposing (Mode)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Pages.StaticHttp.Request as HashRequest
import Pages.StaticHttpRequest as StaticHttpRequest
import Secrets


type alias StaticResponses =
    Dict String StaticHttpResult


type StaticHttpResult
    = NotFetched (StaticHttpRequest.Request ()) (Dict String (Result () String))


type alias Content =
    List ( List String, { extension : String, frontMatter : String, body : Maybe String } )


staticResponsesInit :
    Dict String (Maybe String)
    -> Result (List BuildError) (List ( PagePath pathKey, metadata ))
    ->
        { config
            | content : Content
            , generateFiles :
                List
                    { path : PagePath pathKey
                    , frontmatter : metadata
                    , body : String
                    }
                ->
                    StaticHttp.Request
                        (List
                            (Result String
                                { path : List String
                                , content : String
                                }
                            )
                        )
        }
    -> List ( PagePath pathKey, StaticHttp.Request value )
    -> StaticResponses
staticResponsesInit staticHttpCache siteMetadataResult config list =
    let
        generateFilesRequest : StaticHttp.Request (List (Result String { path : List String, content : String }))
        generateFilesRequest =
            config.generateFiles siteMetadataWithContent

        generateFilesStaticRequest =
            ( -- we don't want to include the CLI-only StaticHttp responses in the production bundle
              -- since that data is only needed to run these functions during the build step
              -- in the future, this could be refactored to have a type to represent this more clearly
              cliDictKey
            , NotFetched (generateFilesRequest |> StaticHttp.map (\_ -> ())) Dict.empty
            )

        siteMetadataWithContent =
            siteMetadataResult
                |> Result.withDefault []
                |> List.map
                    (\( pagePath, metadata ) ->
                        let
                            contentForPage =
                                config.content
                                    |> List.filterMap
                                        (\( path, { body } ) ->
                                            let
                                                pagePathToGenerate =
                                                    PagePath.toString pagePath

                                                currentContentPath =
                                                    "/" ++ (path |> String.join "/")
                                            in
                                            if pagePathToGenerate == currentContentPath then
                                                Just body

                                            else
                                                Nothing
                                        )
                                    |> List.head
                                    |> Maybe.andThen identity
                        in
                        { path = pagePath
                        , frontmatter = metadata
                        , body = contentForPage |> Maybe.withDefault ""
                        }
                    )
    in
    list
        |> List.map
            (\( path, staticRequest ) ->
                let
                    entry =
                        NotFetched (staticRequest |> StaticHttp.map (\_ -> ())) Dict.empty

                    updatedEntry =
                        staticHttpCache
                            |> dictCompact
                            |> Dict.toList
                            |> List.foldl
                                (\( hashedRequest, response ) entrySoFar ->
                                    entrySoFar
                                        |> addEntry
                                            staticHttpCache
                                            hashedRequest
                                            (Ok response)
                                )
                                entry
                in
                ( PagePath.toString path
                , updatedEntry
                )
            )
        |> List.append [ generateFilesStaticRequest ]
        |> Dict.fromList


addEntry : Dict String (Maybe String) -> String -> Result () String -> StaticHttpResult -> StaticHttpResult
addEntry globalRawResponses hashedRequest rawResponse ((NotFetched request rawResponses) as entry) =
    let
        realUrls =
            globalRawResponses
                |> dictCompact
                |> StaticHttpRequest.resolveUrls ApplicationType.Cli request
                |> Tuple.second
                |> List.map Secrets.maskedLookup
                |> List.map HashRequest.hash

        includesUrl =
            List.member
                hashedRequest
                realUrls
    in
    if includesUrl then
        let
            updatedRawResponses =
                Dict.insert
                    hashedRequest
                    rawResponse
                    rawResponses
        in
        NotFetched request updatedRawResponses

    else
        entry


encodeStaticResponses : Mode -> StaticResponses -> Dict String (Dict String String)
encodeStaticResponses mode staticResponses =
    staticResponses
        |> Dict.filter
            (\key value ->
                key /= cliDictKey
            )
        |> Dict.map
            (\path result ->
                case result of
                    NotFetched request rawResponsesDict ->
                        let
                            relevantResponses =
                                Dict.map
                                    (\_ ->
                                        -- TODO avoid running this code at all if there are errors here
                                        Result.withDefault ""
                                    )
                                    rawResponsesDict

                            strippedResponses : Dict String String
                            strippedResponses =
                                -- TODO should this return an Err and handle that here?
                                StaticHttpRequest.strippedResponses ApplicationType.Cli request relevantResponses
                        in
                        case mode of
                            Mode.Dev ->
                                relevantResponses

                            Mode.Prod ->
                                strippedResponses
            )


dictCompact : Dict String (Maybe a) -> Dict String a
dictCompact dict =
    dict
        |> Dict.Extra.filterMap (\key value -> value)


cliDictKey : String
cliDictKey =
    "////elm-pages-CLI////"
