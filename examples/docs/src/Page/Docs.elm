module Page.Docs exposing (Data, Model, Msg, page)

import Css.Global
import DataSource exposing (DataSource)
import DataSource.File
import Document exposing (Document)
import Glob
import Head
import Head.Seo as Seo
import Html.Styled as H exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Markdown.Block exposing (HeadingLevel(..))
import Markdown.Parser
import Markdown.Renderer
import MarkdownHelpers
import OptimizedDecoder
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath
import Pages.PagePath as PagePath exposing (PagePath)
import TableOfContents
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import TailwindMarkdownRenderer


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    {}


page : Page RouteParams Data
page =
    Page.withData
        { head = head
        , staticRoutes = DataSource.succeed [ {} ]
        , data = \_ -> data
        }
        |> Page.buildNoState { view = view }


head :
    StaticPayload Data RouteParams
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


type alias Data =
    List Markdown.Block.Block


view :
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    { title = "TODO title"
    , body =
        [ Css.Global.global Tw.globalStyles
        , div
            [ css
                [ Tw.relative
                , Tw.flex
                , Tw.w_full

                --, Tw.max_w_container
                , Tw.max_w_full
                , Tw.mx_auto
                , Tw.px_4
                , Bp.lg
                    [ Tw.px_8
                    ]
                , Bp.sm
                    [ Tw.px_6
                    ]
                ]
            ]
            [ div
                [ css
                    [ Bp.lg
                        [ Tw.grid
                        , Tw.grid_cols_3
                        , Tw.gap_8
                        ]
                    , Tw.w_full
                    , Tw.flex_none
                    ]
                ]
                [ TableOfContents.view
                    (TableOfContents.buildToc
                        static.static
                    )
                , div
                    [ css
                        [ Bp.lg
                            [ Tw.neg_ml_8
                            , Tw.shadow_md
                            ]
                        , Tw.relative
                        , Tw.col_span_2
                        , Tw.bg_white
                        ]
                    ]
                    [ div
                        [ css
                            [ Tw.hidden
                            , Tw.absolute
                            , Tw.top_0
                            , Tw.bottom_0
                            , Tw.neg_right_4
                            , Tw.w_8
                            , Tw.bg_white
                            , Bp.lg
                                [ Tw.block
                                ]
                            ]
                        ]
                        []
                    , div
                        [ css
                            [ Tw.relative
                            , Tw.py_16
                            , Bp.lg
                                [ Tw.px_16
                                ]
                            ]
                        ]
                        [ div
                            [ css
                                [ Tw.prose
                                , Tw.prose_sm
                                , Tw.max_w_xl
                                , Tw.whitespace_normal
                                , Tw.mx_auto
                                ]
                            ]
                            (static.static
                                |> Markdown.Renderer.render TailwindMarkdownRenderer.renderer
                                |> Result.withDefault []
                            )
                        ]
                    ]
                ]
            ]
        ]
            |> Document.ElmCssView
    }


tocView : PagePath -> MarkdownHelpers.TableOfContents -> H.Html Msg
tocView path toc =
    toc
        |> List.map
            (\heading ->
                H.a
                    ([ --Font.color (Element.rgb255 100 100 100)
                       Attr.href <| PagePath.toString path ++ "#" ++ heading.anchorId
                     , css
                        []
                     ]
                        ++ styleForLevel heading.level
                    )
                    [ H.text heading.name

                    --, H.text <| String.fromInt heading.level
                    ]
            )
        |> H.div
            [ css
                [ Tw.flex
                , Tw.flex_col
                ]
            ]


styleForLevel : Int -> List (Attribute Msg)
styleForLevel headingLevel =
    case headingLevel of
        2 ->
            [ css
                [ Tw.font_bold
                , Tw.text_lg
                ]
            ]

        3 ->
            []

        4 ->
            []

        5 ->
            []

        _ ->
            []


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
    fileRequest "content/docs.md"
