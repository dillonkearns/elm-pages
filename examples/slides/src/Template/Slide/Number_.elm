module Template.Slide.Number_ exposing (Model, Msg, template)

import Document exposing (Document)
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Markdown.Block
import Markdown.Parser
import Markdown.Renderer
import MarkdownRenderer
import OptimizedDecoder
import Pages.ImagePath as ImagePath
import Pages.StaticFile as StaticFile
import Pages.StaticHttp as StaticHttp
import Template exposing (StaticPayload, Template)


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    { number : String }


template : Template RouteParams StaticData
template =
    Template.withStaticData
        { head = head
        , staticRoutes = StaticHttp.succeed [ { number = "1" } ]
        , staticData = staticData
        }
        |> Template.buildNoState { view = view }


staticData : RouteParams -> StaticHttp.Request StaticData
staticData route =
    StaticFile.request
        "slides.md"
        (StaticFile.body
            |> OptimizedDecoder.andThen
                (\rawBody ->
                    case rawBody |> Markdown.Parser.parse of
                        Ok okBlocks ->
                            case
                                okBlocks
                                    |> markdownIndexedByHeading (route.number |> String.toInt |> Maybe.withDefault 1)
                                    |> Markdown.Renderer.render MarkdownRenderer.renderer
                            of
                                Ok renderedBody ->
                                    OptimizedDecoder.succeed renderedBody

                                Err error ->
                                    OptimizedDecoder.fail error

                        Err _ ->
                            OptimizedDecoder.fail ""
                )
        )


markdownIndexedByHeading :
    Int
    -> List Markdown.Block.Block
    -> List Markdown.Block.Block
markdownIndexedByHeading index markdownBlocks =
    Markdown.Block.foldl
        (\block ( currentIndex, markdownToKeep ) ->
            case block of
                Markdown.Block.Heading Markdown.Block.H2 _ ->
                    let
                        newIndex =
                            currentIndex + 1
                    in
                    --_ ->
                    if newIndex == index then
                        ( newIndex, block :: markdownToKeep )

                    else
                        ( newIndex, markdownToKeep )

                _ ->
                    if currentIndex == index then
                        ( currentIndex, block :: markdownToKeep )

                    else
                        ( currentIndex, markdownToKeep )
        )
        ( 0, [] )
        markdownBlocks
        |> Tuple.second
        |> List.reverse


head :
    StaticPayload StaticData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = ImagePath.build [ "TODO" ]
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


type alias StaticData =
    List (Element Msg)


view :
    StaticPayload StaticData RouteParams
    -> Document Msg
view static =
    { title = "TODO title"
    , body =
        [ Element.column
            [ Element.padding 40
            ]
            [ Element.text static.routeParams.number
            , Element.column []
                static.static
            ]
        ]
    }
