module Global exposing (..)

import DocumentSvg
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Events
import Element.Font as Font
import Element.Region
import FontAwesome
import Html exposing (Html)
import Html.Attributes as Attr
import MarkdownRenderer
import OptimizedDecoder as D
import Pages exposing (pages)
import Pages.Directory as Directory exposing (Directory)
import Pages.ImagePath as ImagePath
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Palette
import Secrets


type alias Model =
    { showMobileMenu : Bool
    , counter : Int
    }


map : (msg1 -> msg2) -> PageView msg1 -> PageView msg2
map fn doc =
    { title = doc.title
    , body = Element.map fn doc.body
    }



--mapRendered : (msg1 -> msg2) -> RenderedBody msg1 -> RenderedBody msg2
--mapRendered fn ( first, second ) =
--    ( first, second |> List.map (Element.map fn) )


type alias View msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )


type alias RenderedBody =
    ( MarkdownRenderer.TableOfContents, List (Element Never) )


type alias PageView msg =
    { title : String, body : Element msg }


type Msg
    = OnPageChange
        { path : PagePath Pages.PathKey
        , query : Maybe String
        , fragment : Maybe String
        }
    | ToggleMobileMenu
    | Increment


init : a -> Model
init maybePagePath =
    { showMobileMenu = False
    , counter = 0
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnPageChange page ->
            ( { model | showMobileMenu = False }, Cmd.none )

        ToggleMobileMenu ->
            ( { model | showMobileMenu = not model.showMobileMenu }, Cmd.none )

        Increment ->
            ( { model | counter = model.counter + 1 }, Cmd.none )


type alias StaticData =
    Int


staticData : a -> StaticHttp.Request StaticData
staticData siteMetadata =
    StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (D.field "stargazers_count" D.int)


view :
    StaticData
    -> { a | path : PagePath Pages.PathKey }
    -> Model
    -> (Msg -> msg)
    -> PageView msg
    -> { body : Html msg, title : String }
view stars page model toMsg pageView =
    { body =
        (if model.showMobileMenu then
            Element.column
                [ Element.width Element.fill
                , Element.padding 20
                ]
                [ Element.row [ Element.width Element.fill, Element.spaceEvenly ]
                    [ logoLinkMobile |> Element.map toMsg
                    , FontAwesome.styledIcon "fas fa-bars" [ Element.Events.onClick ToggleMobileMenu ]
                        |> Element.map toMsg
                    ]
                , Element.column [ Element.centerX, Element.spacing 20 ]
                    (navbarLinks stars page.path)
                ]

         else
            Element.column [ Element.width Element.fill ]
                [ header stars page.path |> Element.map toMsg
                , incrementView model |> Element.map toMsg
                , pageView.body
                ]
        )
            |> Element.layout
                [ Element.width Element.fill
                , Font.size 20
                , Font.family [ Font.typeface "Roboto" ]
                , Font.color (Element.rgba255 0 0 0 0.8)
                ]
    , title = pageView.title
    }


incrementView : Model -> Element Msg
incrementView model =
    Element.el [ Element.Events.onClick Increment ] (Element.text <| "Global count: " ++ String.fromInt model.counter)


logoLinkMobile =
    Element.link []
        { url = "/"
        , label =
            Element.row
                [ Font.size 30
                , Element.spacing 16
                , Element.htmlAttribute (Attr.class "navbar-title")
                ]
                [ Element.text "elm-pages"
                ]
        }


navbarLinks stars currentPath =
    [ elmDocsLink
    , githubRepoLink stars
    , highlightableLink currentPath pages.docs.directory "Docs"
    , highlightableLink currentPath pages.showcase.directory "Showcase"
    , highlightableLink currentPath pages.blog.directory "Blog"
    ]


header : Int -> PagePath Pages.PathKey -> Element Msg
header stars currentPath =
    Element.column [ Element.width Element.fill ]
        [ responsiveHeader
        , Element.column
            [ Element.width Element.fill
            , Element.htmlAttribute (Attr.class "responsive-desktop")
            ]
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
                [ logoLink
                , Element.row [ Element.spacing 15 ] (navbarLinks stars currentPath)
                ]
            ]
        ]


logoLink =
    Element.link []
        { url = "/"
        , label =
            Element.row
                [ Font.size 30
                , Element.spacing 16
                , Element.htmlAttribute (Attr.class "navbar-title")
                ]
                [ DocumentSvg.view
                , Element.text "elm-pages"
                ]
        }


responsiveHeader =
    Element.row
        [ Element.width Element.fill
        , Element.spaceEvenly
        , Element.htmlAttribute (Attr.class "responsive-mobile")
        , Element.width Element.fill
        , Element.padding 20
        ]
        [ logoLinkMobile
        , FontAwesome.icon "fas fa-bars" |> Element.el [ Element.alignRight, Element.Events.onClick ToggleMobileMenu ]
        ]


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
