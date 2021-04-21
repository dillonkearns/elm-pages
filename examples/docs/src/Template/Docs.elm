module Template.Docs exposing (Model, Msg, StaticData, template)

import Css.Global
import DataSource exposing (DataSource)
import DataSource.File
import Document exposing (Document)
import Glob
import Head
import Head.Seo as Seo
import Html.Styled as H
import Html.Styled.Attributes exposing (css)
import Markdown.Parser
import Markdown.Renderer
import OptimizedDecoder
import Pages.ImagePath as ImagePath
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
    List (H.Html Msg)


view :
    StaticPayload StaticData RouteParams
    -> Document Msg
view static =
    { title = "TODO title"
    , body =
        [ Css.Global.global Tw.globalStyles
        , H.div
            [ css
                [ Tw.p_8
                , Tw.prose
                ]
            ]
            static.static
        ]
            |> Document.ElmCssView
    }


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


fileRequest : String -> DataSource (List (H.Html Msg))
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
                            |> Result.andThen
                                (Markdown.Renderer.render TailwindMarkdownRenderer.renderer)
                    of
                        Ok renderedBody ->
                            OptimizedDecoder.succeed renderedBody

                        Err error ->
                            OptimizedDecoder.fail error
                )
        )


data : DataSource (List (H.Html Msg))
data =
    docsGlob
        |> DataSource.map
            (\documents ->
                documents
                    |> List.map (\document -> fileRequest document.filePath)
            )
        |> DataSource.resolve
        |> DataSource.map List.concat
