module Template.Showcase exposing (Model, Msg, template)

import Element exposing (Element)
import Head
import Head.Seo as Seo
import MarkdownRenderer
import OptimizedDecoder
import Pages exposing (images)
import Pages.StaticFile as StaticFile
import Pages.StaticHttp as StaticHttp
import Shared
import Showcase
import Template exposing (StaticPayload, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


template : TemplateWithState {} StaticData () Msg
template =
    Template.withStaticData
        { head = head
        , staticData = \_ -> staticData
        }
        |> Template.buildNoState { view = view }


staticData : StaticHttp.Request StaticData
staticData =
    Showcase.staticRequest



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
    List Showcase.Entry


view :
    StaticPayload StaticData
    -> Shared.PageView Msg
view static =
    { title = "elm-pages blog"
    , body =
        let
            showcaseEntries =
                static.static
        in
        [ Element.column [ Element.width Element.fill ]
            [ Element.column [ Element.padding 20, Element.centerX ] [ Showcase.view showcaseEntries ]
            ]
        ]
    }


head : StaticPayload StaticData -> List (Head.Tag Pages.PathKey)
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
