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
import Html exposing (..)
import Html.Attributes as Attr
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

  - `metadata`: Used in view title and head (persistent, sent to client)
  - `body`: Used only inside View.freeze (ephemeral, DCE'd)

The renderFullPage helper uses an extensible record type `{ a | metadata : ..., body : ... }`
instead of `Data`, so it still compiles when the Data type is narrowed.

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
        [ -- Frozen content - body field is ephemeral (only used in freeze)
          -- The helper uses an inline record type, not the Data alias, so it still
          -- compiles when Data is narrowed
          View.freeze (renderFullPage app.data)
        ]
    }


{-| Render the entire page body as frozen content.
All of this code is eliminated from the client bundle via DCE.

Note: We use an inline record type instead of Data so this function still
compiles when the Data type alias is narrowed (ephemeral fields removed).
-}
renderFullPage : { a | metadata : ArticleMetadata, body : List Markdown.Block.Block } -> Html Never
renderFullPage pageData =
    let
        author =
            Author.dillon
    in
    div
        [ Attr.class "min-h-screen w-full relative"
        ]
        [ div
            [ Attr.class "pt-16 pb-16 px-8 flex flex-col"
            ]
            [ div
                [ Attr.class "md:mx-auto"
                ]
                [ -- Title
                  Html.h1
                    [ Attr.class "text-center text-4xl font-bold tracking-tight mt-2 mb-8"
                    ]
                    [ Html.text pageData.metadata.title ]

                -- Author info
                , div
                    [ Attr.class "flex mb-16"
                    ]
                    [ img
                        [ Attr.src (author.avatar |> Pages.Url.toString)
                        , Attr.class "rounded-full h-10 w-10"
                        ]
                        []
                    , div
                        [ Attr.class "ml-3"
                        ]
                        [ div []
                            [ p
                                [ Attr.class "text-sm font-medium text-gray-900"
                                ]
                                [ span [] [ text author.name ]
                                ]
                            ]
                        , div
                            [ Attr.class "flex space-x-1 text-sm text-gray-500"
                            ]
                            [ time
                                [ Attr.datetime "2020-03-16"
                                ]
                                [ text (pageData.metadata.published |> Date.format "MMMM ddd, yyyy") ]
                            ]
                        ]
                    ]

                -- Markdown body
                , div
                    [ Attr.class "prose" ]
                    (pageData.body
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
