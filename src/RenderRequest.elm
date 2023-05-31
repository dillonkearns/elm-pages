module RenderRequest exposing
    ( IncludeHtml(..)
    , RenderRequest(..)
    , RequestPayload(..)
    , decoder
    , default
    , maybeRequestPayload
    )

import ApiRoute
import HtmlPrinter
import Internal.ApiRoute
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.ProgramConfig exposing (ProgramConfig)
import Regex
import Url exposing (Url)
import UrlPath exposing (UrlPath)


type RequestPayload route
    = Page { path : UrlPath, frontmatter : route }
    | Api ( String, ApiRoute.ApiRoute ApiRoute.Response )
    | NotFound UrlPath


type RenderRequest route
    = SinglePage IncludeHtml (RequestPayload route) Decode.Value


default : RenderRequest route
default =
    SinglePage
        HtmlAndJson
        (NotFound (UrlPath.fromString "/error"))
        Encode.null


maybeRequestPayload : RenderRequest route -> Maybe Decode.Value
maybeRequestPayload renderRequest =
    case renderRequest of
        SinglePage _ _ rawJson ->
            Just rawJson


type IncludeHtml
    = HtmlAndJson
    | OnlyJson


decoder :
    ProgramConfig userMsg userModel (Maybe route) pageData actionData sharedData effect mappedMsg errorPage
    -> Decode.Decoder (RenderRequest (Maybe route))
decoder config =
    Decode.field "request"
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



{-
   payload: modifiedRequest,
   kind: "single-page",
   jsonOnly: isJson,
-}


requestPayloadDecoder :
    ProgramConfig userMsg userModel (Maybe route) pageData actionData sharedData effect mappedMsg errorPage
    -> Decode.Decoder (RequestPayload (Maybe route))
requestPayloadDecoder config =
    (Decode.string
        |> Decode.map
            (\rawPath ->
                let
                    path : String
                    path =
                        rawPath
                            |> dropTrailingIndexHtml

                    route : Maybe route
                    route =
                        pathToUrl path |> config.urlToRoute

                    apiRoute : Maybe (ApiRoute.ApiRoute ApiRoute.Response)
                    apiRoute =
                        Internal.ApiRoute.firstMatch (String.dropLeft 1 path)
                            (config.apiRoutes HtmlPrinter.htmlToString)
                in
                case route of
                    Just _ ->
                        if isFile rawPath then
                            case apiRoute of
                                Just justApi ->
                                    ( path, justApi ) |> Api

                                Nothing ->
                                    NotFound (UrlPath.fromString path)

                        else
                            Page
                                { frontmatter = route
                                , path = config.routeToPath route |> UrlPath.join
                                }

                    Nothing ->
                        case apiRoute of
                            Just justApi ->
                                ( path, justApi ) |> Api

                            Nothing ->
                                NotFound (UrlPath.fromString path)
            )
    )
        |> Decode.field "path"
        |> Decode.field "payload"


isFile : String -> Bool
isFile rawPath =
    rawPath
        |> String.contains "."


pathToUrl : String -> Url
pathToUrl path =
    { protocol = Url.Https
    , host = "TODO"
    , port_ = Nothing
    , path = path
    , query = Nothing
    , fragment = Nothing
    }


dropTrailingIndexHtml : String -> String
dropTrailingIndexHtml =
    Regex.replace (Regex.fromString "/index\\.html$" |> Maybe.withDefault Regex.never)
        (\_ -> "")
