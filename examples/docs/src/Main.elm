port module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Element exposing (Element)
import Element.Border
import Element.Font as Font
import Html exposing (Html)
import Json.Encode
import List.Extra
import Mark
import Mark.Error
import MarkParser
import Markdown
import Metadata exposing (Metadata)
import Pages
import Pages.Content as Content exposing (Content)
import Pages.HeadTag as HeadTag exposing (HeadTag)
import Pages.Parser exposing (PageOrPost)
import RawContent
import Url exposing (Url)
import Yaml.Decode


port toJsPort : Json.Encode.Value -> Cmd msg


type alias Flags =
    {}


main : Pages.Program Flags Model Msg (Metadata Msg) (Element Msg)
main =
    Pages.program
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , parser = MarkParser.document
        , frontmatterParser = frontmatterParser
        , content = RawContent.content
        , markdownToHtml = markdownToHtml
        , toJsPort = toJsPort
        , headTags = headTags
        , siteUrl = "https://incrementalelm.com"
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


frontmatterParser : Yaml.Decode.Decoder (Metadata.Metadata msg)
frontmatterParser =
    Yaml.Decode.field "title" Yaml.Decode.string
        |> Yaml.Decode.map Metadata.PageMetadata
        |> Yaml.Decode.map Metadata.Page


type alias Model =
    {}


init : Pages.Flags Flags -> ( Model, Cmd Msg )
init flags =
    ( Model, Cmd.none )


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Model -> PageOrPost (Metadata Msg) (Element Msg) -> { title : String, body : Html Msg }
view model pageOrPost =
    let
        { title, body } =
            pageOrPostView model pageOrPost
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


pageOrPostView : Model -> PageOrPost (Metadata Msg) (Element Msg) -> { title : String, body : Element Msg }
pageOrPostView model pageOrPost =
    case pageOrPost.metadata of
        Metadata.Page metadata ->
            { title = metadata.title
            , body =
                [ header
                , Element.column
                    [ Element.padding 50
                    , Element.spacing 60
                    ]
                    pageOrPost.view
                ]
                    |> Element.textColumn
                        [ Element.width Element.fill
                        ]
            }

        Metadata.Article metadata ->
            { title = metadata.title.raw
            , body =
                (header :: pageOrPost.view)
                    |> Element.textColumn
                        [ Element.width Element.fill
                        , Element.spacing 80
                        ]
            }


header : Element msg
header =
    Element.row [ Element.padding 20, Element.spaceEvenly ]
        [ Element.el [ Font.size 30 ]
            (Element.link [] { url = "/", label = Element.text "elm-pages" })
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
headTags : String -> Metadata.Metadata msg -> List HeadTag
headTags canonicalUrl metadata =
    let
        siteName =
            "Incremental Elm Consulting"

        themeColor =
            "#ffffff"
    in
    [ HeadTag.node "meta" [ ( "name", "theme-color" ), ( "content", themeColor ) ]
    , HeadTag.node "meta"
        [ ( "property", "og:site_name" )
        , ( "content", siteName )
        ]
    , HeadTag.node "meta"
        [ ( "property", "og:url" )
        , ( "content", canonicalUrl )
        ]
    , HeadTag.node "link"
        [ ( "rel", "canonical" )
        , ( "href", canonicalUrl )
        ]
    ]
        ++ pageTags metadata


ensureAtPrefix : String -> String
ensureAtPrefix twitterUsername =
    if twitterUsername |> String.startsWith "@" then
        twitterUsername

    else
        "@" ++ twitterUsername


pageTags metadata =
    case metadata of
        Metadata.Page record ->
            []

        Metadata.Article meta ->
            let
                description =
                    meta.description.raw

                title =
                    meta.title.raw

                twitterUsername =
                    "dillontkearns"

                twitterSiteAccount =
                    "incrementalelm"

                image =
                    ""
            in
            [ HeadTag.node "meta"
                [ ( "property", "og:title" )
                , ( "content", title )
                ]
            , HeadTag.node "meta"
                [ ( "name", "description" )
                , ( "content", description )
                ]
            , HeadTag.node "meta"
                [ ( "property", "og:description" )
                , ( "content", description )
                ]
            , HeadTag.node "meta"
                [ ( "property", "og:image" )
                , ( "content", image )
                ]
            , HeadTag.node "meta"
                [ ( "name", "image" )
                , ( "content", image )
                ]
            , HeadTag.node "meta"
                [ ( "property", "og:type" )
                , ( "content", "article" )
                ]
            , HeadTag.node "meta"
                [ ( "name", "twitter:card" )
                , ( "content", "summary_large_image" )
                ]
            , HeadTag.node "meta"
                [ ( "name", "twitter:creator" )
                , ( "content", ensureAtPrefix twitterUsername )
                ]
            , HeadTag.node "meta"
                [ ( "name", "twitter:site" )
                , ( "content", ensureAtPrefix twitterSiteAccount )
                ]
            , HeadTag.node "meta"
                [ ( "name", "twitter:description" )
                , ( "content", meta.title.raw )
                ]
            , HeadTag.node "meta"
                [ ( "name", "twitter:image" )
                , ( "content", image )
                ]
            , HeadTag.node "meta"
                [ ( "name", "twitter:image:alt" )
                , ( "content", description )
                ]
            ]
