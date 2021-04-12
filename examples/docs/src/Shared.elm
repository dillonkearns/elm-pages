module Shared exposing (Model, Msg(..), PageView, SharedMsg(..), StaticData, template)

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
import OptimizedDecoder as D
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Palette
import Secrets
import SharedTemplate exposing (SharedTemplate)


template : SharedTemplate Msg Model StaticData route msg
template =
    { init = init
    , update = update
    , view = view
    , staticData = staticData
    , subscriptions = subscriptions
    , onPageChange = Just OnPageChange
    }


type alias PageView msg =
    { title : String, body : List (Element msg) }


type Msg
    = OnPageChange
        { path : PagePath
        , query : Maybe String
        , fragment : Maybe String
        }
    | ToggleMobileMenu
    | Increment
    | SharedMsg SharedMsg


type alias StaticData =
    Int


type SharedMsg
    = IncrementFromChild


type alias Model =
    { showMobileMenu : Bool
    , counter : Int
    }


init :
    Maybe
        { path :
            { path : PagePath
            , query : Maybe String
            , fragment : Maybe String
            }
        , metadata : route
        }
    -> ( Model, Cmd Msg )
init maybePagePath =
    ( { showMobileMenu = False
      , counter = 0
      }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OnPageChange _ ->
            ( { model | showMobileMenu = False }, Cmd.none )

        ToggleMobileMenu ->
            ( { model | showMobileMenu = not model.showMobileMenu }, Cmd.none )

        Increment ->
            ( { model | counter = model.counter + 1 }, Cmd.none )

        SharedMsg globalMsg ->
            case globalMsg of
                IncrementFromChild ->
                    ( { model | counter = model.counter + 1 }, Cmd.none )


subscriptions : PagePath -> Model -> Sub Msg
subscriptions _ _ =
    Sub.none


staticData : StaticHttp.Request StaticData
staticData =
    StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (D.field "stargazers_count" D.int)


view :
    StaticData
    ->
        { path : PagePath
        , frontmatter : route
        }
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
                (List.concat
                    [ [ header stars page.path |> Element.map toMsg

                      --, incrementView model |> Element.map toMsg
                      ]
                    , pageView.body
                    ]
                )
        )
            |> Element.layout
                [ Element.width Element.fill
                , Font.size 20
                , Font.family [ Font.typeface "Roboto" ]
                , Font.color (Element.rgba255 0 0 0 0.8)
                ]
    , title = pageView.title
    }


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
    , highlightableLink currentPath [ "docs" ] "Docs"
    , highlightableLink currentPath [ "showcase" ] "Showcase"
    , highlightableLink currentPath [ "blog" ] "Blog"
    ]


header : Int -> PagePath -> Element Msg
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
                    { src = "/images/github.svg", description = "Github repo" }
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
                { src = "/images/elm-logo.svg", description = "Elm Package Docs" }
        }


highlightableLink :
    PagePath
    -> List String
    -> String
    -> Element msg
highlightableLink currentPath linkDirectory displayName =
    let
        isHighlighted =
            (currentPath |> PagePath.toPath)
                == linkDirectory
                || (currentPath
                        |> PagePath.toPath
                        |> List.reverse
                        |> List.drop 1
                        |> List.reverse
                   )
                == linkDirectory
    in
    Element.link
        (if isHighlighted then
            [ Font.underline
            , Font.color Palette.color.primary
            ]

         else
            []
        )
        { url = linkDirectory |> String.join "/"
        , label = Element.text displayName
        }
