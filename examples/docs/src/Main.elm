module Main exposing (main)

import Color
import DocSidebar
import DocumentSvg
import Dotted
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Font as Font
import Element.Region
import Head
import Head.OpenGraph as OpenGraph
import Html exposing (Html)
import Html.Attributes
import Json.Decode
import Markdown.Parser
import MarkdownRenderer
import Metadata exposing (Metadata)
import Pages exposing (Page)
import Pages.Document
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import PagesNew exposing (images, pages)
import Palette


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



--main : Pages.Program Model Msg (Metadata Msg) (List (Element Msg))
-- the intellij-elm plugin doesn't support type aliases for Programs so we need to use this line


main : Platform.Program Pages.Flags (Pages.Model Model Msg (Metadata Msg) ( MarkdownRenderer.TableOfContents, List (Element Msg) )) (Pages.Msg Msg (Metadata Msg) ( MarkdownRenderer.TableOfContents, List (Element Msg) ))
main =
    PagesNew.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , documents = [ markdownDocument ]
        , head = head
        , manifest = manifest
        }


markdownDocument : Pages.Document.DocumentParser (Metadata msg) ( MarkdownRenderer.TableOfContents, List (Element Msg) )
markdownDocument =
    Pages.Document.parser
        { extension = "md"
        , metadata =
            Json.Decode.oneOf
                [ Json.Decode.map3
                    (\author title description ->
                        Metadata.Article
                            { author = author
                            , title = title
                            , description = description
                            }
                    )
                    (Json.Decode.field "author" Json.Decode.string)
                    (Json.Decode.field "title" Json.Decode.string)
                    (Json.Decode.field "description" Json.Decode.string)
                , Json.Decode.map2
                    (\title maybeType ->
                        case maybeType of
                            Just "doc" ->
                                Metadata.Doc { title = title }

                            _ ->
                                Metadata.Page { title = title }
                    )
                    (Json.Decode.field "title" Json.Decode.string)
                    (Json.Decode.field "type" Json.Decode.string
                        |> Json.Decode.maybe
                    )
                ]
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


view : Model -> List ( List String, Metadata Msg ) -> Page (Metadata Msg) ( MarkdownRenderer.TableOfContents, List (Element Msg) ) -> { title : String, body : Html Msg }
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
                , Font.size 18
                , Font.family [ Font.typeface "Roboto" ]
                , Font.color (Element.rgba255 0 0 0 0.8)
                ]
    }


pageView : Model -> List ( List String, Metadata Msg ) -> Page (Metadata Msg) ( MarkdownRenderer.TableOfContents, List (Element Msg) ) -> { title : String, body : Element Msg }
pageView model siteMetadata page =
    case page.metadata of
        Metadata.Page metadata ->
            { title = metadata.title
            , body =
                [ header
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
                    [ header
                    , Element.column
                        [ Element.padding 30
                        , Element.spacing 60
                        , Element.Region.mainContent
                        , Element.width (Element.fill |> Element.maximum 800)
                        , Element.centerX
                        ]
                        (Palette.blogHeading metadata.title
                            :: Tuple.second page.view
                        )
                    ]
            }

        Metadata.Doc metadata ->
            { title = metadata.title
            , body =
                [ header
                , Element.row []
                    [ DocSidebar.view siteMetadata
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


header : Element msg
header =
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
                [ Element.link [] { url = "/docs", label = Element.text "Docs" }
                , Element.link [] { url = "/blog", label = Element.text "Blog" }
                ]
            ]
        ]


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/abouts-cards>
<https://htmlhead.dev>
<https://html.spec.whatwg.org/multipage/semantics.html#standard-metadata-names>
<https://ogp.me/>
-}
head : Metadata Msg -> List Head.Tag
head metadata =
    let
        themeColor =
            "#ffffff"
    in
    [ Head.metaName "theme-color" themeColor
    , Head.canonicalLink canonicalUrl
    ]
        ++ pageTags metadata


canonicalUrl : String
canonicalUrl =
    "https://elm-pages.com"


siteTagline : String
siteTagline =
    "A statically typed site generator - elm-pages"


pageTags : Metadata Msg -> List Head.Tag
pageTags metadata =
    case metadata of
        Metadata.Page _ ->
            OpenGraph.summaryLarge
                { url = canonicalUrl
                , siteName = "elm-pages"
                , image =
                    { url = ""
                    , alt = ""
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = siteTagline
                , locale = Nothing
                , title = "elm-pages"
                }
                |> OpenGraph.website

        Metadata.Doc _ ->
            OpenGraph.summaryLarge
                { url = canonicalUrl
                , siteName = "elm-pages"
                , image =
                    { url = ""
                    , alt = ""
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , locale = Nothing
                , description = siteTagline
                , title = "elm-pages"
                }
                |> OpenGraph.website

        Metadata.Article meta ->
            let
                description =
                    -- TODO
                    -- meta.description.raw
                    ""

                imageUrl =
                    ""

                url =
                    canonicalUrl
            in
            OpenGraph.summaryLarge
                { url = url
                , siteName = "elm-pages"
                , image =
                    { url = imageUrl
                    , alt = description
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = description
                , locale = Nothing
                , title = meta.title
                }
                |> OpenGraph.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Nothing
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }


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
