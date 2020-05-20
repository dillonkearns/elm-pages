module Template.Showcase exposing (..)

import Element exposing (Element)
import Element.Font as Font
import Head
import Head.Seo as Seo
import Html exposing (Html)
import MarkdownRenderer
import Metadata as GlobalMetadata
import OptimizedDecoder as D
import Pages exposing (images)
import Pages.PagePath exposing (PagePath)
import Pages.StaticHttp as StaticHttp
import Secrets
import Showcase


type Metadata
    = Metadata


type Msg
    = Msg



-- TODO wire in custom Model and Msg types
--type Model
--    = Model


type alias Model =
    { showMobileMenu : Bool
    }


type alias View msg =
    ( MarkdownRenderer.TableOfContents, List (Element msg) )


view :
    List ( PagePath Pages.PathKey, GlobalMetadata.Metadata )
    ->
        { path : PagePath Pages.PathKey
        , frontmatter : Metadata
        }
    ->
        StaticHttp.Request
            { view :
                Model
                -> View msg
                -> { title : String, body : Html msg }
            , head : List (Head.Tag Pages.PathKey)
            }
view siteMetadata page =
    case page.frontmatter of
        Metadata ->
            StaticHttp.map2
                (\stars showcaseData ->
                    { view =
                        \model viewForPage ->
                            { title = "elm-pages blog"
                            , body =
                                Element.column [ Element.width Element.fill ]
                                    [ Element.column [ Element.padding 20, Element.centerX ] [ Showcase.view showcaseData ]
                                    ]
                            }
                                |> wrapBody stars page model
                    , head = head page.path page.frontmatter
                    }
                )
                (StaticHttp.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
                    (D.field "stargazers_count" D.int)
                )
                Showcase.staticRequest


siteTagline : String
siteTagline =
    "A statically typed site generator - elm-pages"


head : PagePath Pages.PathKey -> Metadata -> List (Head.Tag Pages.PathKey)
head currentPath metadata =
    case metadata of
        Metadata ->
            Seo.summary
                { canonicalUrlOverride = Nothing
                , siteName = "elm-pages"
                , image =
                    { url = images.iconPng
                    , alt = "elm-pages logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = "See some neat sites built using elm-pages! (Or submit yours!)"
                , locale = Nothing
                , title = "elm-pages sites showcase"
                }
                |> Seo.website


canonicalSiteUrl : String
canonicalSiteUrl =
    "https://elm-pages.com"


wrapBody : Int -> { a | path : PagePath Pages.PathKey } -> Model -> { c | body : Element msg, title : String } -> { body : Html msg, title : String }
wrapBody stars page model record =
    { body =
        Element.column [ Element.width Element.fill ] [ record.body ]
            |> Element.layout
                [ Element.width Element.fill
                , Font.size 20
                , Font.family [ Font.typeface "Roboto" ]
                , Font.color (Element.rgba255 0 0 0 0.8)
                ]
    , title = record.title
    }



--wrapBody : Int -> { a | path : PagePath Pages.PathKey } -> Model -> { c | body : Element Msg, title : String } -> { body : Html Msg, title : String }
--wrapBody stars page model record =
--    { body =
--        (if model.showMobileMenu then
--            Element.column
--                [ Element.width Element.fill
--                , Element.padding 20
--                ]
--                [ Element.row [ Element.width Element.fill, Element.spaceEvenly ]
--                    [ logoLinkMobile
--                    , FontAwesome.styledIcon "fas fa-bars" [ Element.Events.onClick ToggleMobileMenu ]
--                    ]
--                , Element.column [ Element.centerX, Element.spacing 20 ]
--                    (navbarLinks stars page.path)
--                ]
--
--         else
--            Element.column [ Element.width Element.fill ]
--                [ header stars page.path
--                , record.body
--                ]
--        )
--            |> Element.layout
--                [ Element.width Element.fill
--                , Font.size 20
--                , Font.family [ Font.typeface "Roboto" ]
--                , Font.color (Element.rgba255 0 0 0 0.8)
--                ]
--    , title = record.title
--    }
