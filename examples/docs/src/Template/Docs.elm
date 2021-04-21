module Template.Docs exposing (Model, Msg, StaticData, template)

import Css.Global
import DataSource exposing (DataSource)
import DataSource.File
import Document exposing (Document)
import Glob
import Head
import Head.Seo as Seo
import Html.Styled as H
import Html.Styled.Attributes as Attr exposing (css)
import Markdown.Block exposing (HeadingLevel(..))
import Markdown.Parser
import Markdown.Renderer
import MarkdownHelpers
import OptimizedDecoder
import Pages.ImagePath as ImagePath
import Pages.PagePath as PagePath exposing (PagePath)
import Tailwind.Utilities as Tw
import TailwindMarkdownRenderer
import Template exposing (StaticPayload, Template, TemplateWithState)


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    {}


template : Template RouteParams StaticData
template =
    Template.withStaticData
        { head = head
        , staticRoutes = DataSource.succeed [ {} ]
        , staticData =
            \_ -> data
        }
        |> Template.buildNoState { view = view }


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
    List Markdown.Block.Block


view :
    StaticPayload StaticData RouteParams
    -> Document Msg
view static =
    { title = "TODO title"
    , body =
        [ Css.Global.global Tw.globalStyles
        , tocView
            (PagePath.build [ "docs" ])
            (MarkdownHelpers.buildToc
                static.static
            )
        , H.div
            [ css
                [ Tw.p_8
                , Tw.prose
                ]
            ]
            (static.static
                |> Markdown.Renderer.render TailwindMarkdownRenderer.renderer
                |> Result.withDefault []
            )
        ]
            |> Document.ElmCssView
    }


tocView : PagePath -> MarkdownHelpers.TableOfContents -> H.Html Msg
tocView path toc =
    toc
        |> List.map
            (\heading ->
                H.a
                    [ --Font.color (Element.rgb255 100 100 100)
                      Attr.href <| PagePath.toString path ++ "#" ++ heading.anchorId
                    ]
                    [ H.text heading.name
                    , H.text <| String.fromInt heading.level
                    ]
            )
        |> H.div
            [ css
                [ Tw.flex
                , Tw.flex_col
                ]
            ]



{-
   Element.column [ Element.alignTop, Element.spacing 20 ]
       [ Element.el [ Font.bold, Font.size 22 ] (Element.text "Table of Contents")
       , Element.column [ Element.spacing 10 ]
           (toc
               |> List.map
                   (\heading ->
                       Element.link [ Font.color (Element.rgb255 100 100 100) ]
                           { url = PagePath.toString path ++ "#" ++ heading.anchorId
                           , label = Element.text heading.name
                           }
                   )
           )
       ]
-}


type alias DocsFile =
    { filePath : String
    , rank : String
    , slug : String
    }


docsGlob : DataSource.DataSource (List DocsFile)
docsGlob =
    Glob.succeed DocsFile
        |> Glob.capture Glob.fullFilePath
        |> Glob.ignore (Glob.literal "content/docs/")
        |> Glob.capture Glob.wildcard
        |> Glob.ignore (Glob.literal "-")
        |> Glob.capture Glob.wildcard
        |> Glob.ignore (Glob.literal ".md")
        |> Glob.toDataSource



--fileRequest : String -> DataSource (List (H.Html Msg))


fileRequest : String -> DataSource (List Markdown.Block.Block)
fileRequest filePath =
    DataSource.File.request
        filePath
        (DataSource.File.body
            |> OptimizedDecoder.andThen
                (\rawBody ->
                    case
                        rawBody
                            |> Markdown.Parser.parse
                            |> Result.map (List.map transformMarkdown)
                            |> Result.mapError (\_ -> "Markdown parsing error")
                    of
                        Ok renderedBody ->
                            OptimizedDecoder.succeed renderedBody

                        Err error ->
                            OptimizedDecoder.fail error
                )
        )


transformMarkdown : Markdown.Block.Block -> Markdown.Block.Block
transformMarkdown blocks =
    blocks
        |> Markdown.Block.walk
            (\block ->
                case block of
                    Markdown.Block.Heading level children ->
                        Markdown.Block.Heading (bumpHeadingLevel level) children

                    _ ->
                        block
            )


bumpHeadingLevel : HeadingLevel -> HeadingLevel
bumpHeadingLevel level =
    case level of
        H1 ->
            H2

        H2 ->
            H3

        H3 ->
            H4

        H4 ->
            H5

        H5 ->
            H6

        H6 ->
            H6


data : DataSource (List Markdown.Block.Block)
data =
    docsGlob
        |> DataSource.map
            (\documents ->
                documents
                    |> List.map (\document -> fileRequest document.filePath)
            )
        |> DataSource.resolve
        |> DataSource.map List.concat
