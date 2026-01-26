module Route.Blog.Slug_ exposing (ActionData, Data, Model, Msg, route)

import Article
import BackendTask exposing (BackendTask)
import Cloudinary
import Data.Author as Author exposing (Author)
import Date exposing (Date)
import DateOrDateTime
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Extra
import Markdown.Block
import Markdown.Renderer
import MarkdownCodec
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import SiteOld
import StructuredData
import Tailwind.Breakpoints as Bp
import Tailwind.Theme as Theme
import Tailwind.Utilities as Tw
import TailwindMarkdownRenderer
import UnsplashImage
import UrlPath
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { slug : String }


{-| Data type with both persistent and ephemeral fields.

  - `metadata`: Used in head and title (persistent, sent to client)
  - `body`: Used only inside View.freeze (ephemeral, DCE'd)

-}
type alias Data =
    { metadata : ArticleMetadata
    , body : List Markdown.Block.Block
    }


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { data = data
        , head = head
        , pages = pages
        }
        |> RouteBuilder.buildNoState { view = view }


pages : BackendTask FatalError (List RouteParams)
pages =
    Article.blogPostsGlob
        |> BackendTask.map
            (List.map
                (\globData ->
                    { slug = globData.slug }
                )
            )


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = app.data.metadata.title
    , body =
        [ -- Frozen content - uses app.data.body (ephemeral) and app.data.metadata (persistent)
          -- Pass fields individually so the codemod can track which are ephemeral
          View.freeze (renderFullPage app.data.metadata app.data.body)
        ]
    }


{-| Render the entire page body as frozen content.
All of this code is eliminated from the client bundle via DCE.
-}
renderFullPage : ArticleMetadata -> List Markdown.Block.Block -> Html Never
renderFullPage metadata body =
    let
        author =
            Author.dillon
    in
    div
        [ css
            [ Tw.min_h_screen
            , Tw.w_full
            , Tw.relative
            ]
        ]
        [ div
            [ css
                [ Tw.pt_16
                , Tw.pb_16
                , Tw.px_8
                , Tw.flex
                , Tw.flex_col
                ]
            ]
            [ div
                [ css
                    [ Bp.md [ Tw.mx_auto ]
                    ]
                ]
                [ -- Title
                  Html.Styled.h1
                    [ css
                        [ Tw.text_center
                        , Tw.text_4xl
                        , Tw.font_bold
                        , Tw.tracking_tight
                        , Tw.mt_2
                        , Tw.mb_8
                        ]
                    ]
                    [ Html.Styled.text metadata.title ]

                -- Author info
                , div
                    [ css
                        [ Tw.flex
                        , Tw.mb_16
                        ]
                    ]
                    [ img
                        [ Attr.src (author.avatar |> Pages.Url.toString)
                        , css
                            [ Tw.rounded_full
                            , Tw.h_10
                            , Tw.w_10
                            ]
                        ]
                        []
                    , div
                        [ css [ Tw.ml_3 ]
                        ]
                        [ div []
                            [ p
                                [ css
                                    [ Tw.text_sm
                                    , Tw.font_medium
                                    , Tw.text_color Theme.gray_900
                                    ]
                                ]
                                [ span [] [ text author.name ]
                                ]
                            ]
                        , div
                            [ css
                                [ Tw.flex
                                , Tw.space_x_1
                                , Tw.text_sm
                                , Tw.text_color Theme.gray_500
                                ]
                            ]
                            [ time
                                [ Attr.datetime "2020-03-16"
                                ]
                                [ text (metadata.published |> Date.format "MMMM ddd, yyyy") ]
                            ]
                        ]
                    ]

                -- Markdown body
                , div
                    [ css [ Tw.prose ] ]
                    (body
                        |> Markdown.Renderer.render TailwindMarkdownRenderer.renderer
                        |> Result.withDefault []
                    )
                ]
            ]
        ]


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    let
        metadata =
            app.data.metadata
    in
    Head.structuredData
        (StructuredData.article
            { title = metadata.title
            , description = metadata.description
            , author = StructuredData.person { name = Author.dillon.name }
            , publisher = StructuredData.person { name = Author.dillon.name }
            , url = SiteOld.canonicalUrl ++ UrlPath.toAbsolute app.path
            , imageUrl = metadata.image
            , datePublished = Date.toIsoString metadata.published
            , mainEntityOfPage =
                StructuredData.softwareSourceCode
                    { codeRepositoryUrl = "https://github.com/dillonkearns/elm-pages"
                    , description = "A statically typed site generator for Elm."
                    , author = "Dillon Kearns"
                    , programmingLanguage = StructuredData.elmLang
                    }
            }
        )
        :: (Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = metadata.image
                    , alt = metadata.description
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = metadata.description
                , locale = Nothing
                , title = metadata.title
                }
                |> Seo.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Just (DateOrDateTime.Date metadata.published)
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }
           )


{-| Load metadata and body.
Metadata is used in head (persistent), body is used only in freeze (ephemeral).
-}
data : RouteParams -> BackendTask FatalError Data
data routeParams =
    MarkdownCodec.withFrontmatter
        (\metadata body ->
            { metadata = metadata
            , body = body
            }
        )
        frontmatterDecoder
        TailwindMarkdownRenderer.renderer
        ("content/blog/" ++ routeParams.slug ++ ".md")


type alias ArticleMetadata =
    { title : String
    , description : String
    , published : Date
    , image : Pages.Url.Url
    , draft : Bool
    }


frontmatterDecoder : Decoder ArticleMetadata
frontmatterDecoder =
    Decode.map5 ArticleMetadata
        (Decode.field "title" Decode.string)
        (Decode.field "description" Decode.string)
        (Decode.field "published"
            (Decode.string
                |> Decode.andThen
                    (\isoString ->
                        Date.fromIsoString isoString
                            |> Json.Decode.Extra.fromResult
                    )
            )
        )
        (Decode.oneOf
            [ Decode.field "image" imageDecoder
            , Decode.field "unsplash" UnsplashImage.decoder |> Decode.map UnsplashImage.imagePath
            ]
        )
        (Decode.field "draft" Decode.bool
            |> Decode.maybe
            |> Decode.map (Maybe.withDefault False)
        )


imageDecoder : Decode.Decoder Pages.Url.Url
imageDecoder =
    Decode.string
        |> Decode.map (\cloudinaryAsset -> Cloudinary.url cloudinaryAsset Nothing 800)
