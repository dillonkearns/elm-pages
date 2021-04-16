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
    = SinglePage IncludeHtml (RequestPayload route)
      --ServerOrBuild
      --| SharedData
      --| GenerateFiles
    | FullBuild


type IncludeHtml
    = HtmlAndJson



--| OnlyJson


type ServerOrBuild
    = Server
    | Build


decoder :
    ProgramConfig userMsg userModel route siteStaticData pageStaticData sharedStaticData
    -> Decode.Decoder (RenderRequest route)
decoder config =
    optionalField "request"
        (Decode.field "path"
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
        )
        |> Decode.map
            (\maybeRequest ->
                case maybeRequest of
                    Just request ->
                        SinglePage HtmlAndJson request

                    Nothing ->
                        FullBuild
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
