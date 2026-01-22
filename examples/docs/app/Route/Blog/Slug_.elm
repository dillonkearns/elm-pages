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
import View.Static


{-| All page content wrapped for static rendering.
The entire view body will be a single static region, eliminating all
rendering code from the client bundle.
-}
type alias StaticContent =
    { metadata : ArticleMetadata
    , body : List Markdown.Block.Block
    }


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    { slug : String }


route : StatelessRoute RouteParams Data ActionData {}
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
    App Data ActionData RouteParams {}
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = app.data.title
    , body =
        [ -- The ENTIRE body is a single static region
          -- All rendering code (TailwindMarkdownRenderer, authorView, etc.)
          -- is eliminated from the client bundle via DCE
          View.staticView app.data.staticContent renderFullPage
        ]
    }


{-| Render the entire page body as a single static region.
All of this code is eliminated from the client bundle via DCE.
-}
renderFullPage : StaticContent -> View.Static
renderFullPage content =
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
                    [ Html.Styled.text content.metadata.title ]

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
                                [ text (content.metadata.published |> Date.format "MMMM ddd, yyyy") ]
                            ]
                        ]
                    ]

                -- Markdown body
                , div
                    [ css [ Tw.prose ] ]
                    (content.body
                        |> Markdown.Renderer.render TailwindMarkdownRenderer.renderer
                        |> Result.withDefault []
                    )
                ]
            ]
        ]


head :
    App Data ActionData RouteParams {}
    -> List Head.Tag
head app =
    -- Safe to use staticMap here because head only runs at build time
    -- The elm-review codemod ensures this code path is never reached on client
    View.Static.map app.data.staticContent
        (\content ->
            let
                metadata =
                    content.metadata
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
        )


type alias Data =
    { title : String
    , staticContent : View.Static.StaticOnlyData StaticContent
    }


type alias ActionData =
    {}


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
        |> BackendTask.andThen
            (\parsed ->
                BackendTask.map2
                    (\title staticContent ->
                        { title = title
                        , staticContent = staticContent
                        }
                    )
                    (BackendTask.succeed parsed.metadata.title)
                    -- Wrap ALL content in StaticOnlyData for full DCE
                    -- The elm-review codemod transforms this to BackendTask.fail on client
                    (View.Static.backendTask
                        (BackendTask.succeed
                            { metadata = parsed.metadata
                            , body = parsed.body
                            }
                        )
                    )
            )


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
