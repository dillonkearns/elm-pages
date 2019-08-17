port module Main exposing (main)

import Browser
import DocSidebar
import DocumentSvg
import Element exposing (Element)
import Element.Border
import Element.Font as Font
import Element.Region
import Head
import Head.OpenGraph as OpenGraph
import Head.SocialMeta as SocialMeta
import Html exposing (Html)
import Json.Decode
import Json.Encode
import List.Extra
import Mark
import Mark.Error
import MarkParser
import Markdown
import Metadata exposing (Metadata)
import Pages
import Pages.Content as Content exposing (Content)
import Pages.Parser exposing (Page)
import RawContent
import Url exposing (Url)


port toJsPort : Json.Encode.Value -> Cmd msg


type alias Flags =
    {}


main : Pages.Program Flags Model Msg (Metadata Msg) (Element Msg)
main =
    Pages.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , parser = MarkParser.document
        , frontmatterParser = frontmatterParser
        , content = RawContent.content
        , markdownToHtml = markdownToHtml
        , toJsPort = toJsPort
        , head = head
        }


markdownToHtml : String -> Element msg
markdownToHtml body =
    Markdown.toHtmlWith
        { githubFlavored = Just { tables = True, breaks = False }
        , defaultHighlighting = Nothing
        , sanitize = True
        , smartypants = False
        }
        []
        body
        |> Element.html


frontmatterParser : Json.Decode.Decoder (Metadata.Metadata msg)
frontmatterParser =
    Json.Decode.field "title" Json.Decode.string
        |> Json.Decode.map Metadata.PageMetadata
        |> Json.Decode.map Metadata.Page


type alias Model =
    {}


init : Pages.Flags Flags -> ( Model, Cmd Msg )
init flags =
    ( Model, Cmd.none )


type alias Msg =
    ()


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> List ( List String, Metadata Msg ) -> Page (Metadata Msg) (Element Msg) -> { title : String, body : Html Msg }
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


pageView : Model -> List ( List String, Metadata Msg ) -> Page (Metadata Msg) (Element Msg) -> { title : String, body : Element Msg }
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
                    [ DocSidebar.view siteMetadata
                        |> Element.el [ Element.width (Element.fillPortion 2), Element.alignTop, Element.height Element.fill ]
                    , [ Element.el [] (Element.text metadata.title)
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
head : Metadata.Metadata msg -> List Head.Tag
head metadata =
    let
        themeColor =
            "#ffffff"
    in
    [ Head.metaName "theme-color" themeColor
    , Head.canonicalLink canonicalUrl
    ]
        ++ pageTags metadata


canonicalUrl =
    "https://elm-pages.com"


siteTagline =
    "A statically typed site generator - elm-pages"


pageTags metadata =
    case metadata of
        Metadata.Page record ->
            OpenGraph.website
                (OpenGraph.buildCommon
                    { url = canonicalUrl
                    , siteName = "elm-pages"
                    , image =
                        { url = ""
                        , alt = ""
                        }
                    , description = siteTagline
                    , title = "elm-pages"
                    }
                )
                ++ [ Head.description siteTagline
                   ]

        Metadata.Doc record ->
            OpenGraph.website
                (OpenGraph.buildCommon
                    { url = canonicalUrl
                    , siteName = "elm-pages"
                    , image =
                        { url = ""
                        , alt = ""
                        }
                    , description = siteTagline
                    , title = "elm-pages"
                    }
                )
                ++ [ Head.description siteTagline
                   ]

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
            [ Head.description description
            , Head.metaName "image" imageUrl
            ]
                ++ SocialMeta.summaryLarge
                    { title = meta.title.raw
                    , description = Just description
                    , siteUser = Nothing
                    , image = Just { url = imageUrl, alt = description }
                    }
                ++ OpenGraph.article
                    (OpenGraph.buildCommon
                        { url = url
                        , siteName = "elm-pages"
                        , image =
                            { url = imageUrl
                            , alt = description
                            }
                        , description = description
                        , title = title
                        }
                    )
                    { tags = []
                    , section = Nothing
                    , publishedTime = Nothing
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }
