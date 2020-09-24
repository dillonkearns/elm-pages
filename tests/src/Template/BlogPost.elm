module Template.BlogPost exposing (Model, Msg, decoder, template)

import Data.Author as Author exposing (Author)
import Date exposing (Date)
import Element exposing (Element)
import Element.Font as Font
import Element.Region
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import List.Extra
import OptimizedDecoder as D
import Pages
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Palette
import Secrets
import Site
import StructuredData
import Template
import Template.Metadata exposing (BlogPost)
import TemplateDocument exposing (TemplateDocument)
import TemplateType


type alias Model =
    ()


type alias Msg =
    Never


template : TemplateDocument BlogPost StaticData Model Msg
template =
    Template.withStaticData staticData head
        |> Template.buildNoState { view = view }


decoder : Decode.Decoder BlogPost
decoder =
    Decode.map6 BlogPost
        (Decode.field "title" Decode.string)
        (Decode.field "description" Decode.string)
        (Decode.field "published"
            (Decode.string
                |> Decode.andThen
                    (\isoString ->
                        case Date.fromIsoString isoString of
                            Ok date ->
                                Decode.succeed date

                            Err error ->
                                Decode.fail error
                    )
            )
        )
        (Decode.field "author" Author.decoder)
        (Decode.field "image" imageDecoder)
        (Decode.field "draft" Decode.bool
            |> Decode.maybe
            |> Decode.map (Maybe.withDefault False)
        )


imageDecoder : Decode.Decoder (ImagePath Pages.PathKey)
imageDecoder =
    Decode.string
        |> Decode.andThen
            (\imageAssetPath ->
                case findMatchingImage imageAssetPath of
                    Nothing ->
                        Decode.fail "Couldn't find image."

                    Just imagePath ->
                        Decode.succeed imagePath
            )


findMatchingImage : String -> Maybe (ImagePath Pages.PathKey)
findMatchingImage imageAssetPath =
    List.Extra.find
        (\image -> ImagePath.toString image == imageAssetPath)
        Pages.allImages





staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (D.field "stargazers_count" D.int)


type alias StaticData =
    Int


view : List ( PagePath Pages.PathKey, TemplateType.Metadata ) -> StaticData -> Model -> BlogPost -> ( a, List (Element msg) ) -> { title : String, body : Element msg }
view allMetadata static model blogPost rendered =
    { title = blogPost.title
    , body =
        Element.column [ Element.width Element.fill ]
            [ Element.column
                [ Element.padding 30
                , Element.spacing 40
                , Element.Region.mainContent
                , Element.width (Element.fill |> Element.maximum 800)
                , Element.centerX
                ]
                (Element.column [ Element.spacing 10 ]
                    [ Element.row [ Element.spacing 10 ]
                        [ Author.view [] blogPost.author
                        , Element.column [ Element.spacing 10, Element.width Element.fill ]
                            [ Element.paragraph [ Font.bold, Font.size 24 ]
                                [ Element.text blogPost.author.name
                                ]
                            , Element.paragraph [ Font.size 16 ]
                                [ Element.text blogPost.author.bio ]
                            ]
                        ]
                    ]
                    :: (publishedDateView blogPost |> Element.el [ Font.size 16, Font.color (Element.rgba255 0 0 0 0.6) ])
                    :: Palette.blogHeading blogPost.title
                    :: articleImageView blogPost.image
                    :: Tuple.second rendered
                )
            ]
    }


head : StaticData -> PagePath.PagePath Pages.PathKey -> BlogPost -> List (Head.Tag Pages.PathKey)
head static currentPath meta =
    Head.structuredData
        (StructuredData.article
            { title = meta.title
            , description = meta.description
            , author = StructuredData.person { name = meta.author.name }
            , publisher = StructuredData.person { name = "Dillon Kearns" }
            , url = Site.canonicalUrl ++ "/" ++ PagePath.toString currentPath
            , imageUrl = Site.canonicalUrl ++ "/" ++ ImagePath.toString meta.image
            , datePublished = Date.toIsoString meta.published
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
                    { url = meta.image
                    , alt = meta.description
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = meta.description
                , locale = Nothing
                , title = meta.title
                }
                |> Seo.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Just (Date.toIsoString meta.published)
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }
           )


publishedDateView : { a | published : Date.Date } -> Element msg
publishedDateView metadata =
    Element.text
        (metadata.published
            |> Date.format "MMMM ddd, yyyy"
        )


articleImageView : ImagePath Pages.PathKey -> Element msg
articleImageView articleImage =
    Element.image [ Element.width Element.fill ]
        { src = ImagePath.toString articleImage
        , description = "Article cover photo"
        }
