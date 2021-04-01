module Template.Showcase exposing (Model, Msg, decoder, template)

import Element exposing (Element)
import Head
import Head.Seo as Seo
import Json.Decode as Decode exposing (Decoder)
import MarkdownRenderer
import OptimizedDecoder
import Pages exposing (images)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticFile as StaticFile
import Pages.StaticHttp as StaticHttp
import Secrets
import Shared
import Showcase
import Template exposing (StaticPayload, TemplateWithState)
import TemplateMetadata exposing (Showcase)
import TemplateType exposing (TemplateType)


type alias Model =
    ()


type alias Msg =
    Never


template : TemplateWithState Showcase StaticData () Msg
template =
    Template.withStaticData
        { head = head
        , staticData = staticData
        }
        |> Template.buildNoState { view = view }


decoder : Decoder Showcase
decoder =
    Decode.succeed Showcase


staticData :
    List ( PagePath Pages.PathKey, TemplateType )
    -> StaticHttp.Request StaticData
staticData siteMetadata =
    StaticHttp.map2 Tuple.pair
        Showcase.staticRequest
        fileRequest



--(StaticHttp.get
--    (Secrets.succeed "file://elm.json")
--    OptimizedDecoder.string
--)


type alias DataFromFile =
    { body : List (Element Msg), title : String }


fileRequest : StaticHttp.Request DataFromFile
fileRequest =
    StaticFile.request
        "content/blog/static-http.md"
        (OptimizedDecoder.map2 DataFromFile
            (StaticFile.body
                |> OptimizedDecoder.andThen
                    (\rawBody ->
                        case rawBody |> MarkdownRenderer.view |> Result.map Tuple.second of
                            Ok renderedBody ->
                                OptimizedDecoder.succeed renderedBody

                            Err error ->
                                OptimizedDecoder.fail error
                    )
            )
            (StaticFile.frontmatter (OptimizedDecoder.field "title" OptimizedDecoder.string))
        )


type alias StaticData =
    ( List Showcase.Entry, DataFromFile )


view :
    List ( PagePath Pages.PathKey, TemplateType )
    -> StaticPayload Showcase StaticData
    -> Shared.RenderedBody
    -> Shared.PageView Msg
view allMetadata static rendered =
    { title = "elm-pages blog"
    , body =
        let
            ( showcaseEntries, dataFromFile ) =
                static.static
        in
        [ Element.column [ Element.width Element.fill ]
            [ Element.text <| dataFromFile.title
            , Element.column [] dataFromFile.body

            --, Element.column [ Element.padding 20, Element.centerX ] [ Showcase.view showcaseEntries ]
            ]
        ]
    }


head : StaticPayload Showcase StaticData -> List (Head.Tag Pages.PathKey)
head staticPayload =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "See some neat sites built using elm-pages! (Or submit yours!)"
        , locale = Nothing
        , title = "elm-pages sites showcase"
        }
        |> Seo.website
