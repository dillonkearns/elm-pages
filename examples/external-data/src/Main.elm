module Main exposing (main)

import Color
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Font as Font
import Element.Region
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Json.Decode as Decode exposing (Decoder)
import Pages exposing (images, pages)
import Pages.Directory as Directory exposing (Directory)
import Pages.Document
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform exposing (Page)
import Palette
import Secrets
import StaticHttp


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
    , sourceIcon = images.iconPng
    }


type alias View =
    ()


type alias Metadata =
    ()


main : Pages.Platform.Program Model Msg Metadata View
main =
    Pages.Platform.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , documents = [ markdownDocument ]
        , manifest = manifest
        , canonicalSiteUrl = canonicalSiteUrl
        , onPageChange = OnPageChange
        , internals = Pages.internals
        }


markdownDocument : ( String, Pages.Document.DocumentHandler Metadata () )
markdownDocument =
    Pages.Document.parser
        { extension = "md"
        , metadata = Decode.succeed ()
        , body = \_ -> Ok ()
        }


type alias Model =
    {}


init : Maybe (PagePath Pages.PathKey) -> ( Model, Cmd Msg )
init maybePagePath =
    ( Model, Cmd.none )


type Msg
    = OnPageChange (PagePath Pages.PathKey)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnPageChange page ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


type alias Company =
    { name : String
    , logoUrl : String
    }


companyView : Company -> Element msg
companyView company =
    Element.column []
        [ Element.el [] (Element.text company.name)
        , Element.image []
            { src = company.logoUrl
            , description = company.name ++ " logo"
            }
        ]


airtableRequest : StaticHttp.Request (List Company)
airtableRequest =
    StaticHttp.jsonRequestWithSecrets
        (\secrets ->
            secrets
                |> Secrets.get "AIRTABLE_API_KEY"
                |> Result.map (\airtableApiKey -> "https://api.airtable.com/v0/appNsAv2iE9mFm56N/Table%201?view=Approved&api_key=" ++ airtableApiKey)
        )
        (Decode.field "records"
            (Decode.list
                (Decode.field "fields"
                    (Decode.map2 Company
                        (Decode.field "Company Name" Decode.string)
                        (Decode.field "Company Logo" (Decode.index 0 (Decode.field "url" Decode.string)))
                    )
                )
            )
        )


view :
    List ( PagePath Pages.PathKey, Metadata )
    ->
        { path : PagePath Pages.PathKey
        , frontmatter : Metadata
        }
    ->
        StaticHttp.Request
            { view : Model -> View -> { title : String, body : Html Msg }
            , head : List (Head.Tag Pages.PathKey)
            }
view siteMetadata page =
    let
        viewFn =
            case page.frontmatter of
                () ->
                    StaticHttp.map3
                        (\elmCompanies starCount netlifyStars ->
                            { view =
                                \model viewForPage ->
                                    { title = "Landing Page"
                                    , body =
                                        (header starCount
                                            :: (elmCompanies
                                                    |> List.map companyView
                                               )
                                        )
                                            |> Element.column [ Element.width Element.fill ]
                                            |> Element.layout []
                                    }
                            , head = head page.frontmatter
                            }
                        )
                        airtableRequest
                        (StaticHttp.jsonRequest "https://api.github.com/repos/dillonkearns/elm-pages"
                            (Decode.field "stargazers_count" Decode.int)
                        )
                        (StaticHttp.jsonRequest "https://api.github.com/repos/dillonkearns/elm-markdown"
                            (Decode.field "stargazers_count" Decode.int)
                        )
    in
    viewFn


wrapBody body =
    body
        |> Element.layout
            [ Element.width Element.fill
            , Font.size 20
            , Font.family [ Font.typeface "Roboto" ]
            , Font.color (Element.rgba255 0 0 0 0.8)
            ]


articleImageView : ImagePath Pages.PathKey -> Element msg
articleImageView articleImage =
    Element.image [ Element.width Element.fill ]
        { src = ImagePath.toString articleImage
        , description = "Article cover photo"
        }


header : Int -> Element msg
header starCount =
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
                    Element.row
                        [ Font.size 30
                        , Element.spacing 16
                        , Element.htmlAttribute (Attr.id "navbar-title")
                        ]
                        [ Element.text "elm-pages static data"
                        ]
                }
            , Element.row [ Element.spacing 15 ]
                [ elmDocsLink
                , githubRepoLink starCount
                ]
            ]
        ]


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/abouts-cards>
<https://htmlhead.dev>
<https://html.spec.whatwg.org/multipage/semantics.html#standard-metadata-names>
<https://ogp.me/>
-}
head : () -> List (Head.Tag Pages.PathKey)
head () =
    Seo.summaryLarge
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = images.iconPng
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = siteTagline
        , locale = Nothing
        , title = "External Data Example"
        }
        |> Seo.website


canonicalSiteUrl : String
canonicalSiteUrl =
    "https://elm-pages.com"


siteTagline : String
siteTagline =
    "A statically typed site generator - elm-pages"


githubRepoLink : Int -> Element msg
githubRepoLink starCount =
    Element.newTabLink []
        { url = "https://github.com/dillonkearns/elm-pages"
        , label =
            Element.row [ Element.spacing 5 ]
                [ Element.image
                    [ Element.width (Element.px 22)
                    , Font.color Palette.color.primary
                    ]
                    { src = ImagePath.toString Pages.images.github, description = "Github repo" }
                , Element.text <| String.fromInt starCount
                ]
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
