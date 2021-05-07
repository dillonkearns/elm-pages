module Page.Docs.Section_ exposing (Data, Model, Msg, page)

import Css.Global
import DataSource exposing (DataSource)
import DataSource.File
import DataSource.Glob as Glob
import Document exposing (Document)
import Element exposing (Element)
import Head
import Head.Seo as Seo
import List.Extra
import Markdown.Block as Block
import Markdown.Parser
import OptimizedDecoder
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.ImagePath as ImagePath
import Shared
import TableOfContents
import Tailwind.Utilities as Tw


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    { section : String }


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
        |> DataSource.map (List.map (.slug >> RouteParams))


type alias Section =
    { filePath : String
    , order : Int
    , slug : String
    }


data : RouteParams -> DataSource Data
data routeParams =
    DataSource.map Data
        toc


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
    }


view :
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    --View.placeholder "Docs.Section_"
    { title = ""
    , body =
        Document.ElmCssView
            [ Css.Global.global Tw.globalStyles
            , TableOfContents.view static.static.toc
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


toData level styledList =
    { anchorId = TableOfContents.styledToString styledList |> TableOfContents.rawTextToId
    , name = TableOfContents.styledToString styledList
    , level = level
    }
