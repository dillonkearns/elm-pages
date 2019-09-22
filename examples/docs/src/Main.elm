module Main exposing (main)

import Color
import Data.Author as Author
import Date
import DocSidebar
import DocumentSvg
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Font as Font
import Element.Region
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Index
import Json.Decode
import MarkdownRenderer
import Metadata exposing (Metadata)
import Pages exposing (images, pages)
import Pages.Directory as Directory exposing (Directory)
import Pages.Document
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform exposing (Page)
import Palette


manifest : Manifest.Config Pages.PathKey
manifest =
    { backgroundColor = Just Color.white
    , categories = [ Pages.Manifest.Category.education ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Just Color.white
    , startUrl = pages.index
    , shortName = Just "elm-pages"
    , sourceIcon = images.icon
    }



--main : Pages.Platform.Program Model Msg (Metadata ) (List (Element Msg))
-- the intellij-elm plugin doesn't support type aliases for Programs so we need to use this line


main : Platform.Program Pages.Platform.Flags (Pages.Platform.Model Model Msg Metadata ( MarkdownRenderer.TableOfContents, List (Element Msg) )) (Pages.Platform.Msg Msg Metadata ( MarkdownRenderer.TableOfContents, List (Element Msg) ))
main =
    Pages.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , documents = [ markdownDocument ]
        , head = head
        , manifest = manifest
        , canonicalSiteUrl = canonicalSiteUrl
        }


markdownDocument : ( String, Pages.Document.DocumentHandler Metadata ( MarkdownRenderer.TableOfContents, List (Element Msg) ) )
markdownDocument =
    Pages.Document.parser
        { extension = "md"
        , metadata = Metadata.decoder
        , body = MarkdownRenderer.view
        }


type alias Model =
    {}


init : ( Model, Cmd Msg )
init =
    ( Model, Cmd.none )


type alias Msg =
    ()


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        () ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> List ( PagePath Pages.PathKey, Metadata ) -> Page Metadata ( MarkdownRenderer.TableOfContents, List (Element Msg) ) Pages.PathKey -> { title : String, body : Html Msg }
view model siteMetadata page =
    let
        { title, body } =
            pageView model siteMetadata page
    in
    { title = title
    , body =
        body
            |> Element.layout
                [ Element.width Element.fill
                , Font.size 20
                , Font.family [ Font.typeface "Roboto" ]
                , Font.color (Element.rgba255 0 0 0 0.8)
                ]
    }


pageView : Model -> List ( PagePath Pages.PathKey, Metadata ) -> Page Metadata ( MarkdownRenderer.TableOfContents, List (Element Msg) ) Pages.PathKey -> { title : String, body : Element Msg }
pageView model siteMetadata page =
    case page.metadata of
        Metadata.Page metadata ->
            { title = metadata.title
            , body =
                [ header page.path
                , Element.column
                    [ Element.padding 50
                    , Element.spacing 60
                    , Element.Region.mainContent
                    ]
                    (Tuple.second page.view)
                ]
                    |> Element.textColumn
                        [ Element.width Element.fill
                        ]
            }

        Metadata.Article metadata ->
            { title = metadata.title
            , body =
                Element.column [ Element.width Element.fill ]
                    [ header page.path
                    , Element.column
                        [ Element.padding 30
                        , Element.spacing 40
                        , Element.Region.mainContent
                        , Element.width (Element.fill |> Element.maximum 800)
                        , Element.centerX
                        ]
                        (Element.column [ Element.spacing 10 ]
                            [ Element.row [ Element.spacing 10 ]
                                [ Author.view [] metadata.author
                                , Element.column [ Element.spacing 10, Element.width Element.fill ]
                                    [ Element.paragraph [ Font.bold, Font.size 24 ]
                                        [ Element.text metadata.author.name
                                        ]
                                    , Element.paragraph [ Font.size 16 ]
                                        [ Element.text metadata.author.bio ]
                                    ]
                                ]
                            ]
                            :: (publishedDateView metadata |> Element.el [ Font.size 16, Font.color (Element.rgba255 0 0 0 0.6) ])
                            :: Palette.blogHeading metadata.title
                            :: Tuple.second page.view
                        )
                    ]
            }

        Metadata.Doc metadata ->
            { title = metadata.title
            , body =
                [ header page.path
                , Element.row []
                    [ DocSidebar.view page.path siteMetadata
                        |> Element.el [ Element.width (Element.fillPortion 2), Element.alignTop, Element.height Element.fill ]
                    , Element.column [ Element.width (Element.fillPortion 8), Element.padding 35, Element.spacing 15 ]
                        [ Palette.heading 1 [ Element.text metadata.title ]
                        , Element.column [ Element.spacing 20 ]
                            [ tocView (Tuple.first page.view)
                            , Element.column
                                [ Element.padding 50
                                , Element.spacing 30
                                , Element.Region.mainContent
                                ]
                                (Tuple.second page.view)
                            ]
                        ]
                    ]
                ]
                    |> Element.textColumn
                        [ Element.width Element.fill
                        , Element.height Element.fill
                        ]
            }

        Metadata.Author author ->
            { title = author.name
            , body =
                Element.column
                    [ Element.width Element.fill
                    ]
                    [ header page.path
                    , Element.column
                        [ Element.padding 30
                        , Element.spacing 20
                        , Element.Region.mainContent
                        , Element.width (Element.fill |> Element.maximum 800)
                        , Element.centerX
                        ]
                        [ Palette.blogHeading author.name
                        , Author.view [] author
                        , Element.paragraph [ Element.centerX, Font.center ] (Tuple.second page.view)
                        ]
                    ]
            }

        Metadata.BlogIndex ->
            { title = "elm-pages blog"
            , body =
                Element.column [ Element.width Element.fill ]
                    [ header page.path
                    , Element.column [ Element.padding 20, Element.centerX ] [ Index.view siteMetadata ]
                    ]
            }


header : PagePath Pages.PathKey -> Element msg
header currentPath =
    Element.column [ Element.width Element.fill ]
        [ Element.el
            [ Element.height (Element.px 4)
            , Element.width Element.fill
            , Element.Background.gradient
                { angle = 0.2
                , steps =
                    [ Element.rgb255 0 242 96
                    , Element.rgb255 5 117 230
                    ]
                }
            ]
            Element.none
        , Element.row
            [ Element.paddingXY 25 4
            , Element.spaceEvenly
            , Element.width Element.fill
            , Element.Region.navigation
            , Element.Border.widthEach { bottom = 1, left = 0, right = 0, top = 0 }
            , Element.Border.color (Element.rgba255 40 80 40 0.4)
            ]
            [ Element.link []
                { url = "/"
                , label =
                    Element.row [ Font.size 30, Element.spacing 16 ]
                        [ DocumentSvg.view
                        , Element.text "elm-pages"
                        ]
                }
            , Element.row [ Element.spacing 15 ]
                [ elmDocsLink
                , githubRepoLink
                , highlightableLink currentPath pages.docs.directory "Docs"
                , highlightableLink currentPath pages.blog.directory "Blog"
                ]
            ]
        ]


highlightableLink :
    PagePath Pages.PathKey
    -> Directory Pages.PathKey Directory.WithIndex
    -> String
    -> Element msg
highlightableLink currentPath linkDirectory displayName =
    let
        isHighlighted =
            currentPath |> Directory.includes linkDirectory
    in
    Element.link
        (if isHighlighted then
            [ Font.underline
            , Font.color Palette.color.primary
            ]

         else
            []
        )
        { url = linkDirectory |> Directory.indexPath |> PagePath.toString
        , label = Element.text displayName
        }


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/abouts-cards>
<https://htmlhead.dev>
<https://html.spec.whatwg.org/multipage/semantics.html#standard-metadata-names>
<https://ogp.me/>
-}
head : Metadata -> List (Head.Tag Pages.PathKey)
head metadata =
    case metadata of
        Metadata.Page meta ->
            Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = images.icon
                    , alt = "elm-pages logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = siteTagline
                , locale = Nothing
                , title = meta.title
                }
                |> Seo.website

        Metadata.Doc meta ->
            Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = images.icon
                    , alt = "elm pages logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , locale = Nothing
                , description = siteTagline
                , title = meta.title
                }
                |> Seo.website

        Metadata.Article meta ->
            Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = Pages.images.icon
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

        Metadata.Author meta ->
            let
                ( firstName, lastName ) =
                    case meta.name |> String.split " " of
                        [ first, last ] ->
                            ( first, last )

                        [ first, middle, last ] ->
                            ( first ++ " " ++ middle, last )

                        [] ->
                            ( "", "" )

                        _ ->
                            ( meta.name, "" )
            in
            Seo.summary
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = meta.avatar
                    , alt = meta.name ++ "'s elm-pages articles."
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = meta.bio
                , locale = Nothing
                , title = meta.name ++ "'s elm-pages articles."
                }
                |> Seo.profile
                    { firstName = firstName
                    , lastName = lastName
                    , username = Nothing
                    }

        Metadata.BlogIndex ->
            Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = images.icon
                    , alt = "elm-pages logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = siteTagline
                , locale = Nothing
                , title = "elm-pages blog"
                }
                |> Seo.website


canonicalSiteUrl : String
canonicalSiteUrl =
    "https://elm-pages.com"


siteTagline : String
siteTagline =
    "A statically typed site generator - elm-pages"


tocView : MarkdownRenderer.TableOfContents -> Element msg
tocView toc =
    Element.column [ Element.alignTop, Element.spacing 20 ]
        [ Element.el [ Font.bold, Font.size 22 ] (Element.text "Table of Contents")
        , Element.column [ Element.spacing 10 ]
            (toc
                |> List.map
                    (\heading ->
                        Element.link [ Font.color (Element.rgb255 100 100 100) ]
                            { url = "#" ++ heading.anchorId
                            , label = Element.text heading.name
                            }
                    )
            )
        ]


publishedDateView metadata =
    Element.text
        (metadata.published
            |> Date.format "MMMM ddd, yyyy"
        )


githubRepoLink : Element msg
githubRepoLink =
    Element.newTabLink []
        { url = "https://github.com/dillonkearns/elm-pages"
        , label =
            Element.image
                [ Element.width (Element.px 22)
                , Font.color Palette.color.primary
                ]
                { src = ImagePath.toString Pages.images.github, description = "Github repo" }
        }


elmDocsLink : Element msg
elmDocsLink =
    Element.newTabLink []
        { url = "https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/"
        , label =
            Element.image
                [ Element.width (Element.px 22)
                , Font.color Palette.color.primary
                ]
                { src = ImagePath.toString Pages.images.elmLogo, description = "Elm Package Docs" }
        }
