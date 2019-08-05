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
import Pages.Head as Head
import Pages.Parser exposing (PageOrPost)
import RawContent
import Url exposing (Url)
import Yaml.Decode


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


siteUrl =
    "https://incrementalelm.com"


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
                ]
    }


pageOrPostView : Model -> PageOrPost (Metadata Msg) (Element Msg) -> { title : String, body : Element Msg }
pageOrPostView model pageOrPost =
    case pageOrPost.metadata of
        Metadata.Page metadata ->
            { title = metadata.title
            , body =
                (header :: pageOrPost.view)
                    |> Element.textColumn [ Element.width Element.fill ]
            }

        Metadata.Article metadata ->
            { title = metadata.title.raw
            , body =
                (header :: pageOrPost.view)
                    |> Element.textColumn [ Element.width Element.fill ]
            }


header : Element msg
header =
    Element.row [ Element.padding 20, Element.Border.width 2, Element.spaceEvenly ]
        [ Element.el [ Font.size 30 ]
            (Element.link [] { url = "/", label = Element.text "elm-markup-site" })
        , Element.row [ Element.spacing 15 ]
            [ Element.link [] { url = "/articles", label = Element.text "Articles" }
            , Element.link [] { url = "/about", label = Element.text "About" }
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
        siteName =
            "Incremental Elm Consulting"

        themeColor =
            "#ffffff"
    in
    [ Head.metaName "theme-color" themeColor
    , Head.metaProperty "og:site_name" siteName
    , Head.metaProperty "og:url" siteUrl
    , Head.canonicalLink siteUrl
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
            [ Head.metaProperty "og:title" title
            , Head.metaName "description" description
            , Head.metaProperty "og:description" description
            , Head.metaProperty "og:image" image
            , Head.metaName "image" image
            , Head.metaProperty "og:type" "article"
            , Head.metaName "twitter:card" "summary_large_image"
            , Head.metaName "twitter:creator" (ensureAtPrefix twitterUsername)
            , Head.metaName "twitter:site" (ensureAtPrefix twitterSiteAccount)
            , Head.metaName "twitter:description" meta.title.raw
            , Head.metaName "twitter:image" image
            , Head.metaName "twitter:image:alt" description
            ]
