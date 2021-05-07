module Page.Docs.Section__ exposing (Data, Model, Msg, page)

import Css
import Css.Global
import DataSource exposing (DataSource)
import DataSource.File
import DataSource.Glob as Glob
import Document exposing (Document)
import Element exposing (Element)
import Head
import Head.Seo as Seo
import Html.Styled as Html
import Html.Styled.Attributes exposing (css)
import List.Extra
import Markdown.Block as Block exposing (Block)
import Markdown.Parser
import Markdown.Renderer
import OptimizedDecoder
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath
import Shared
import TableOfContents
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import TailwindMarkdownRenderer


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    { section : Maybe String }


page : Page RouteParams Data
page =
    Page.prerenderedRoute
        { head = head
        , routes = routes
        , data = data
        }
        |> Page.buildNoState { view = view }


routes : DataSource (List RouteParams)
routes =
    docFiles
        |> DataSource.map (List.map (.slug >> Just >> RouteParams))
        |> DataSource.map
            (\sections ->
                { section = Nothing } :: sections
            )


type alias Section =
    { filePath : String
    , order : Int
    , slug : String
    }


data : RouteParams -> DataSource Data
data routeParams =
    DataSource.map2 Data
        toc
        (pageBody routeParams)


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
    { toc : TableOfContents.TableOfContents TableOfContents.Data
    , body : List Block
    }


view :
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    --View.placeholder "Docs.Section_"
    { title = ""
    , body =
        Document.ElmCssView
            [ Css.Global.global
                [ Css.Global.selector ".anchor-icon"
                    [ Css.opacity Css.zero
                    ]
                , Css.Global.selector "h2:hover .anchor-icon"
                    [ Css.opacity (Css.num 100)
                    ]
                ]
            , Html.div
                [ css
                    [ Tw.flex
                    , Tw.flex_1
                    , Tw.h_full
                    ]
                ]
                [ TableOfContents.view static.routeParams.section static.static.toc
                , Html.article
                    [ css
                        [ Tw.prose
                        , Tw.prose_sm
                        , Tw.max_w_xl

                        --, Tw.whitespace_normal
                        --, Tw.mx_auto
                        , Tw.relative
                        , Tw.pt_8
                        , Tw.pb_16
                        , Tw.px_6
                        , Tw.w_full
                        , Tw.max_w_full
                        , Tw.overflow_x_hidden
                        , Bp.md
                            [ Tw.px_8
                            ]
                        ]
                    ]
                    (static.static.body
                        |> Markdown.Renderer.render TailwindMarkdownRenderer.renderer
                        |> Result.withDefault [ Html.text "" ]
                    )
                ]
            ]
    }


toc : DataSource (TableOfContents.TableOfContents TableOfContents.Data)
toc =
    docFiles
        |> DataSource.map
            (\sections ->
                sections
                    |> List.sortBy .order
                    |> List.reverse
                    |> List.map
                        (\section ->
                            DataSource.File.request
                                section.filePath
                                (headingsDecoder section.slug)
                        )
            )
        |> DataSource.resolve


docFiles : DataSource (List Section)
docFiles =
    Glob.succeed Section
        |> Glob.capture Glob.fullFilePath
        |> Glob.ignore (Glob.literal "content/docs/")
        |> Glob.capture Glob.int
        |> Glob.ignore (Glob.literal "-")
        |> Glob.capture Glob.wildcard
        |> Glob.ignore (Glob.literal ".md")
        |> Glob.toDataSource


pageBody : RouteParams -> DataSource (List Block)
pageBody routeParams =
    let
        slug : String
        slug =
            routeParams.section
                |> Maybe.withDefault "what-is-elm-pages"

        matchingFile : Glob.Glob ()
        matchingFile =
            Glob.succeed ()
                |> Glob.ignore (Glob.literal "content/docs/")
                |> Glob.ignore Glob.int
                |> Glob.ignore (Glob.literal "-")
                |> Glob.ignore (Glob.literal slug)
                |> Glob.ignore (Glob.literal ".md")
    in
    Glob.expectUniqueFile matchingFile
        |> DataSource.andThen
            (\filePath ->
                DataSource.File.request filePath
                    markdownBodyDecoder
            )


markdownBodyDecoder =
    DataSource.File.body
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


headingsDecoder : String -> OptimizedDecoder.Decoder (TableOfContents.Entry TableOfContents.Data)
headingsDecoder slug =
    DataSource.File.body
        |> OptimizedDecoder.andThen
            (\rawBody ->
                case
                    rawBody
                        |> Markdown.Parser.parse
                        |> Result.mapError (\_ -> "Markdown parsing error")
                        |> Result.map TableOfContents.gatherHeadings
                        |> Result.andThen (nameAndTopLevel slug)
                of
                    Ok renderedBody ->
                        OptimizedDecoder.succeed renderedBody

                    Err error ->
                        OptimizedDecoder.fail error
            )


nameAndTopLevel :
    String
    -> List ( Block.HeadingLevel, List Block.Inline )
    -> Result String (TableOfContents.Entry TableOfContents.Data)
nameAndTopLevel slug headings =
    let
        h1 : Maybe (List Block.Inline)
        h1 =
            List.Extra.findMap
                (\( level, inlines ) ->
                    case level of
                        Block.H1 ->
                            Just inlines

                        _ ->
                            Nothing
                )
                headings

        h2s : List (List Block.Inline)
        h2s =
            List.filterMap
                (\( level, inlines ) ->
                    case level of
                        Block.H2 ->
                            Just inlines

                        _ ->
                            Nothing
                )
                headings
    in
    case h1 of
        Just justH1 ->
            Ok
                (TableOfContents.Entry
                    { anchorId = slug
                    , name = TableOfContents.styledToString justH1
                    , level = 1
                    }
                    (h2s
                        |> List.map (toData 2)
                        |> List.map (\l2Data -> TableOfContents.Entry l2Data [])
                    )
                )

        _ ->
            Err ""


toData : Int -> List Block.Inline -> { anchorId : String, name : String, level : Int }
toData level styledList =
    { anchorId = TableOfContents.styledToString styledList |> TableOfContents.rawTextToId
    , name = TableOfContents.styledToString styledList
    , level = level
    }
