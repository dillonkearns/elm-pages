module RenderRequest exposing (..)

import Json.Decode as Decode
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.ProgramConfig exposing (ProgramConfig)
import Url exposing (Url)


type alias RequestPayload route =
    { path : PagePath
    , frontmatter : route
    }


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
    ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData
    -> Decode.Decoder (RenderRequest route)
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
    ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData
    -> Decode.Decoder (RequestPayload route)
requestPayloadDecoder config =
    (Decode.string
        |> Decode.map
            (\path ->
                let
                    route =
                        pathToUrl path |> config.urlToRoute
                in
                { frontmatter = route
                , path = config.routeToPath route |> PagePath.build
                }
            )
    )
        |> Decode.field "path"
        |> Decode.field "payload"


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
