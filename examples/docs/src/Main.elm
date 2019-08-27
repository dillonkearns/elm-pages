module Main exposing (main)

import Color
import Dict
import DocumentSvg
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Font as Font
import Element.Region
import Head
import Head.OpenGraph as OpenGraph
import Html exposing (Html)
import Json.Decode
import Mark
import MarkParser
import Markdown.Parser
import Metadata exposing (Metadata)
import Pages
import Pages.Document
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.Parser exposing (Page)
import PagesNew exposing (images, pages)


manifest =
    { backgroundColor = Just Color.blue
    , categories = [ Pages.Manifest.Category.education ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Just Color.blue
    , startUrl = pages.index
    , shortName = Just "elm-pages"
    , sourceIcon = images.icon
    }



--main : Pages.Program Model Msg (Metadata Msg) (List (Element Msg))
-- the intellij-elm plugin doesn't support type aliases for Programs so we need to use this line


main : Platform.Program Pages.Flags (Pages.Model Model Msg (Metadata Msg) (List (Element Msg))) (Pages.Msg Msg (Metadata Msg) (List (Element Msg)))
main =
    PagesNew.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , documents = [ markupDocument, markdownDocument ]
        , head = head
        , manifest = manifest
        }


markupDocument : Pages.Document.DocumentParser (Metadata Msg) (List (Element Msg))
markupDocument =
    Pages.Document.markupParser
        (Metadata.metadata Dict.empty |> Mark.document identity)
        (MarkParser.blocks
            { imageAssets = Dict.empty
            , routes = PagesNew.all |> List.map PagesNew.routeToString
            , indexView = []
            }
            |> Mark.manyOf
            |> Mark.document identity
        )


markdownDocument : Pages.Document.DocumentParser (Metadata msg) (List (Element Msg))
markdownDocument =
    Pages.Document.parser
        { extension = "md"
        , metadata =
            Json.Decode.field "title" Json.Decode.string
                |> Json.Decode.map
                    (\title ->
                        Metadata.Page { title = title }
                    )
        , body = \content -> renderMarkdown content
        }


renderMarkdown : String -> Result String (List (Element Msg))
renderMarkdown markdown =
    -- TODO implement this with parser
    -- [ Element.text markdown ]
    markdown
        |> Markdown.Parser.render
            { heading =
                \level content ->
                    Element.paragraph
                        [ Font.size 36
                        , Font.bold
                        , Font.center
                        , Font.family [ Font.typeface "Raleway" ]
                        , Element.Region.heading level
                        ]
                        content
            , todo = Element.text "TODO"
            , htmlDecoder = Markdown.Parser.htmlOneOf []
            , raw = Element.paragraph []
            , bold =
                \content ->
                    Element.row
                        [ Font.bold
                        ]
                        [ Element.text content ]
            , italic =
                \content ->
                    Element.row
                        [ Font.italic
                        ]
                        [ Element.text content ]
            , code = code
            , plain = Element.text
            , link =
                -- TODO use link.title
                \link content ->
                    Element.link [] { url = link.destination, label = Element.text content }
            , list =
                \items ->
                    Element.column []
                        (items
                            |> List.map
                                (\itemBlocks ->
                                    Element.row [ Element.spacing 5 ]
                                        [ Element.text "•", itemBlocks ]
                                )
                        )
            }


code : String -> Element msg
code snippet =
    Element.el
        [ Element.Background.color
            (Element.rgba 0 0 0 0.04)
        , Element.Border.rounded 2
        , Element.paddingXY 5 3
        , Font.color (Element.rgba255 0 0 0 1)
        , Font.family [ Font.monospace ]
        ]
        (Element.text snippet)


type alias Model =
    {}


init : ( Model, Cmd Msg )
init =
    ( Model, Cmd.none )


type alias Msg =
    ()


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> List ( List String, Metadata Msg ) -> Page (Metadata Msg) (List (Element Msg)) -> { title : String, body : Html Msg }
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


pageView : Model -> List ( List String, Metadata Msg ) -> Page (Metadata Msg) (List (Element Msg)) -> { title : String, body : Element Msg }
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
                    page.view
                ]
                    |> Element.textColumn
                        [ Element.width Element.fill
                        ]
            }

        Metadata.Article metadata ->
            { title = metadata.title.raw
            , body =
                (header :: page.view)
                    |> Element.textColumn
                        [ Element.width Element.fill
                        , Element.spacing 80
                        ]
            }

        Metadata.Doc metadata ->
            { title = metadata.title
            , body =
                [ header
                , Element.row []
                    [ -- TODO restore sidebar view
                      -- DocSidebar.view siteMetadata
                      --     |> Element.el [ Element.width (Element.fillPortion 2), Element.alignTop, Element.height Element.fill ],
                      [ Element.el [] (Element.text metadata.title)
                      , Element.column
                            [ Element.padding 50
                            , Element.spacing 60
                            , Element.Region.mainContent
                            ]
                            page.view
                      ]
                        |> Element.column [ Element.width (Element.fillPortion 8) ]
                    ]
                ]
                    |> Element.textColumn
                        [ Element.width Element.fill
                        , Element.height Element.fill
                        ]
            }


header : Element msg
header =
    Element.row
        [ Element.paddingXY 25 4
        , Element.spaceEvenly
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
                    meta.description.raw

                title =
                    meta.title.raw

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
                , title = meta.title.raw
                }
                |> OpenGraph.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Nothing
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }
