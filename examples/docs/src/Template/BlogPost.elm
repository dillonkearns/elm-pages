module Template.BlogPost exposing (Model, Msg, decoder, template)

import Data.Author as Author exposing (Author)
import Date exposing (Date)
import Element exposing (Element)
import Element.Font as Font
import Element.Region
import Global
import GlobalMetadata
import Head
import Head.Seo as Seo
import Json.Decode as Decode
import List.Extra
import Pages
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Palette
import SiteConfig
import StructuredData
import Template exposing (DynamicPayload, StaticPayload, Template)
import TemplateMetadata exposing (BlogPost)


type Model
    = Model


type Msg
    = Msg


template : Template BlogPost () Model Msg
template =
    Template.simpler
        { view = view
        , head = head
        , init = init
        , update = update
        }


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


init : BlogPost -> ( Model, Cmd Msg )
init metadata =
    ( Model, Cmd.none )


update : BlogPost -> Msg -> Model -> ( Model, Cmd Msg )
update metadata msg model =
    ( Model, Cmd.none )


view :
    List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
    -> StaticPayload BlogPost ()
    -> Model
    -> Global.RenderedBody
    -> Global.PageView Msg
view allMetadata staticPayload model rendered =
    { title = staticPayload.metadata.title
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
                        [ Author.view [] staticPayload.metadata.author
                        , Element.column [ Element.spacing 10, Element.width Element.fill ]
                            [ Element.paragraph [ Font.bold, Font.size 24 ]
                                [ Element.text staticPayload.metadata.author.name
                                ]
                            , Element.paragraph [ Font.size 16 ]
                                [ Element.text staticPayload.metadata.author.bio ]
                            ]
                        ]
                    ]
                    :: (publishedDateView staticPayload.metadata |> Element.el [ Font.size 16, Font.color (Element.rgba255 0 0 0 0.6) ])
                    :: Palette.blogHeading staticPayload.metadata.title
                    :: articleImageView staticPayload.metadata.image
                    :: Tuple.second rendered
                    |> List.map (Element.map never)
                )
            ]
    }


head : StaticPayload BlogPost () -> List (Head.Tag Pages.PathKey)
head staticPayload =
    Head.structuredData
        (StructuredData.article
            { title = staticPayload.metadata.title
            , description = staticPayload.metadata.description
            , author = StructuredData.person { name = staticPayload.metadata.author.name }
            , publisher = StructuredData.person { name = "Dillon Kearns" }
            , url = SiteConfig.canonicalUrl ++ "/" ++ PagePath.toString staticPayload.path
            , imageUrl = SiteConfig.canonicalUrl ++ "/" ++ ImagePath.toString staticPayload.metadata.image
            , datePublished = Date.toIsoString staticPayload.metadata.published
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
                    { url = staticPayload.metadata.image
                    , alt = staticPayload.metadata.description
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = staticPayload.metadata.description
                , locale = Nothing
                , title = staticPayload.metadata.title
                }
                |> Seo.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Just (Date.toIsoString staticPayload.metadata.published)
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
