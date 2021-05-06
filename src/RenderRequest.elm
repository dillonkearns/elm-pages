module RenderRequest exposing (..)

import ApiRoute
import DataSource exposing (DataSource)
import Json.Decode as Decode
import Json.Encode
import Pages.Manifest as Manifest
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.ProgramConfig exposing (ProgramConfig)
import Url exposing (Url)


type RequestPayload route
    = Page { path : PagePath, frontmatter : route }
    | Api ( String, ApiRoute.Done ApiRoute.Response )
    | NotFound


type RenderRequest route
    = SinglePage IncludeHtml (RequestPayload route) Decode.Value
      --ServerOrBuild
      --| SharedData
      --| GenerateFiles
    | FullBuild


maybeRequestPayload : RenderRequest route -> Maybe Decode.Value
maybeRequestPayload renderRequest =
    case renderRequest of
        FullBuild ->
            Nothing

        SinglePage _ _ rawJson ->
            Just rawJson


type IncludeHtml
    = HtmlAndJson
    | OnlyJson


type ServerOrBuild
    = Server
    | Build


decoder :
    ProgramConfig userMsg userModel (Maybe route) siteData pageData sharedData
    -> Decode.Decoder (RenderRequest (Maybe route))
decoder config =
    optionalField "request"
        (Decode.map3
            (\includeHtml requestThing payload ->
                SinglePage includeHtml requestThing payload
            )
            (Decode.field "kind" Decode.string
                |> Decode.andThen
                    (\kind ->
                        case kind of
                            "single-page" ->
                                Decode.field "jsonOnly" Decode.bool
                                    |> Decode.map
                                        (\jsonOnly ->
                                            if jsonOnly then
                                                OnlyJson

                                            else
                                                HtmlAndJson
                                        )

                            _ ->
                                Decode.fail "Unhandled"
                    )
            )
            (requestPayloadDecoder config)
            (Decode.field "payload" Decode.value)
        )
        |> Decode.map
            (\maybeRequest ->
                case maybeRequest of
                    Just request ->
                        request

                    Nothing ->
                        FullBuild
            )



{-
   payload: modifiedRequest,
   kind: "single-page",
   jsonOnly: isJson,
-}


requestPayloadDecoder :
    ProgramConfig userMsg userModel (Maybe route) siteData pageData sharedData
    -> Decode.Decoder (RequestPayload (Maybe route))
requestPayloadDecoder config =
    (Decode.string
        |> Decode.map
            (\path ->
                let
                    route : Maybe route
                    route =
                        pathToUrl path |> config.urlToRoute

                    apiRoute : Maybe (ApiRoute.Done ApiRoute.Response)
                    apiRoute =
                        ApiRoute.firstMatch (String.dropLeft 1 path)
                            (manifestHandler config
                                :: site.apiRoutes
                            )

                    site =
                        config.site []
                in
                case route of
                    Just justRoute ->
                        Page
                            { frontmatter = route
                            , path = config.routeToPath route |> PagePath.build
                            }

                    Nothing ->
                        case apiRoute of
                            Just justApi ->
                                ( path, justApi ) |> Api

                            Nothing ->
                                NotFound
            )
    )
        |> Decode.field "path"
        |> Decode.field "payload"


manifestHandler : ProgramConfig userMsg userModel (Maybe route) siteData pageData sharedData -> ApiRoute.Done ApiRoute.Response
manifestHandler config =
    ApiRoute.succeed
        (config.getStaticRoutes
            |> DataSource.andThen
                (\resolvedRoutes ->
                    config.site resolvedRoutes
                        |> .data
                        |> DataSource.map
                            (\data ->
                                (config.site resolvedRoutes |> .manifest) data
                                    |> manifestToFile (config.site resolvedRoutes |> .canonicalUrl)
                            )
                )
        )
        |> ApiRoute.literal "manifest.json"
        |> ApiRoute.singleRoute


manifestToFile : String -> Manifest.Config -> { body : String }
manifestToFile resolvedCanonicalUrl manifestConfig =
    manifestConfig
        |> Manifest.toJson resolvedCanonicalUrl
        |> (\manifestJsonValue ->
                { body = Json.Encode.encode 0 manifestJsonValue
                }
           )


pathToUrl : String -> Url
pathToUrl path =
    { protocol = Url.Https
    , host = "TODO"
    , port_ = Nothing
    , path = path
    , query = Nothing
    , fragment = Nothing
    }


optionalField : String -> Decode.Decoder a -> Decode.Decoder (Maybe a)
optionalField fieldName decoder_ =
    let
        finishDecoding json =
            case Decode.decodeValue (Decode.field fieldName Decode.value) json of
                Ok _ ->
                    -- The field is present, so run the decoder_ on it.
                    Decode.map Just (Decode.field fieldName decoder_)

                Err _ ->
                    -- The field was missing, which is fine!
                    Decode.succeed Nothing
    in
    Decode.value
        |> Decode.andThen finishDecoding
