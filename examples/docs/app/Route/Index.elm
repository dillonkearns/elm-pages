module Route.Index exposing (ActionData, Data, Model, Msg, route)

import Css
import DataSource exposing (DataSource)
import Exception exposing (Throwable)
import Head
import Head.Seo as Seo
import Html.Styled as Html exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Link
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route exposing (Route)
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Shared
import SiteOld
import Svg.Styled exposing (path, svg)
import Svg.Styled.Attributes as SvgAttr
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import View exposing (View)
import View.CodeTab as CodeTab


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias Data =
    ()


type alias ActionData =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = [ "images", "icon-png.png" ] |> Path.join |> Pages.Url.fromPath
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "elm-pages - " ++ SiteOld.tagline
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "elm-pages - a statically typed site generator"
    , body =
        [ landingView |> Html.map Pages.Msg.UserMsg
        ]
    }


data : DataSource Throwable Data
data =
    DataSource.succeed ()


landingView : Html Msg
landingView =
    div
        [ css
            [ Tw.relative
            , Tw.pt_16
            , Tw.pb_32
            , Tw.overflow_hidden
            ]
        ]
        [ div
            [ Attr.attribute "aria-hidden" "true"
            , css
                [ Tw.absolute
                , Tw.inset_x_0
                , Tw.top_0
                , Tw.h_48

                --, Tw.bg_gradient_to_b
                , Tw.bg_gradient_to_b
                , Tw.from_gray_100
                ]
            ]
            []
        , firstSection
            { heading = "Pull in typed Elm data to your pages"
            , body = "Whether your data is coming from markdown files, APIs, a CMS, or all of the above, elm-pages lets you pull in just the data you need for a page. No loading spinners, no Msg or update logic, just define your data and use it in your view."
            , buttonText = "Check out the Docs"
            , buttonLink = Route.Docs__Section__ { section = Nothing }
            , svgIcon = "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
            , code =
                ( "src/Page/Repo/Name_.elm", """module Route.Repo.Name_ exposing (Data, Model, Msg, route)
                
type alias Data = Int
type alias RouteParams = { name : String }

route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.preRender
        { head = head
        , pages = pages
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }

pages : DataSource (List RouteParams)
pages =
    DataSource.succeed [ { name = "elm-pages" } ]

data : RouteParams -> DataSource Data
data routeParams =
    DataSource.Http.get
        (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (Decode.field "stargazer_count" Decode.int)

view :
    StaticPayload Data ActionData RouteParams
    -> View Msg
view static =
    { title = static.routeParams.name
    , body =
        [ h1 [] [ text static.routeParams.name ]
        , p [] [ text ("Stars: " ++ String.fromInt static.data) ]
        ]
    }""" )
            }
        , firstSection
            { heading = "Combine data from multiple sources"
            , body = "Wherever the data came from, you can transform DataSources and combine multiple DataSources using the full power of Elm's type system."
            , buttonText = "Learn more about DataSources"
            , buttonLink = Route.Docs__Section__ { section = Just "data-sources" }
            , svgIcon = "M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
            , code =
                ( "src/Project.elm", """type alias Project =
    { name : String
    , description : String
    , repo : Repo
    }


all : DataSource (List Project)
all =
    Glob.succeed
        (\\projectName filePath ->
            DataSource.map2 (Project projectName)
                (DataSource.File.rawFile filePath DataSource.File.body)
                (repo projectName)
        )
        |> Glob.match (Glob.literal "projects/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".txt")
        |> Glob.captureFilePath
        |> Glob.toDataSource
        |> DataSource.resolve


repo : String -> DataSource Repo
repo repoName =
    DataSource.Http.get (Secrets.succeed ("https://api.github.com/repos/dillonkearns/" ++ repoName))
        (OptimizedDecoder.map Repo
            (OptimizedDecoder.field "stargazers_count" OptimizedDecoder.int)
        )
""" )
            }
        , firstSection
            { heading = "SEO"
            , body = "Make sure your site previews look polished with the type-safe SEO API. `elm-pages build` pre-renders HTML for your pages. And your SEO tags get access to the page's DataSources."
            , buttonText = "Learn about the SEO API"
            , buttonLink = Route.Docs__Section__ { section = Nothing }
            , svgIcon = "M10 21h7a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v11m0 5l4.879-4.879m0 0a3 3 0 104.243-4.242 3 3 0 00-4.243 4.242z"
            , code =
                ( "src/Page/Blog/Slug_.elm", """head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summaryLarge
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = static.data.image
            , alt = static.data.description
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = static.data.description
        , locale = Nothing
        , title = static.data.title
        }
        |> Seo.article
            { tags = []
            , section = Nothing
            , publishedTime = Just (Date.toIsoString static.data.published)
            , modifiedTime = Nothing
            , expirationTime = Nothing
            }

""" )
            }
        , firstSection
            { heading = "Optimized Data"
            , body = "The OptimizedDecoder module is a drop-in replacement for vanilla decoders. Just by using that module, elm-pages will strip out any untouched JSON values from your DataSource's."
            , buttonText = "Learn about OptimizedDecoders"
            , buttonLink = Route.Docs__Section__ { section = Nothing }
            , svgIcon = "M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
            , code =
                ( "src/Page/Blog/Slug_.elm", """import OptimizedDecoder

data : RouteParams -> DataSource Data
data routeParams =
    DataSource.Http.get
        (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (OptimizedDecoder.field "stargazer_count" OptimizedDecoder.int)


{-
Full API response from https://api.github.com/repos/dillonkearns/elm-pages
{
    "id": 198527910,
    "node_id": "MDEwOlJlcG9zaXRvcnkxOTg1Mjc5MTA=",
    "name": "elm-pages",
    "full_name": "dillonkearns/elm-pages",
    "private": false,
    "owner": { ... },
    .....
    "stargazers_count": 394,
    .....
}

Optimized data for initial page load:

{
    "stargazers_count": 394
}

-}

            """ )
            }
        ]


firstSection :
    { heading : String
    , body : String
    , buttonLink : Route
    , buttonText : String
    , svgIcon : String
    , code : ( String, String )
    }
    -> Html Msg
firstSection info =
    div
        [ css
            [ Tw.relative
            ]
        ]
        [ div
            [ css
                [ Bp.lg
                    [ Tw.mx_auto
                    , Tw.max_w_4xl
                    , Tw.px_8
                    ]
                ]
            ]
            [ div
                [ css
                    [ Tw.px_4
                    , Tw.max_w_xl
                    , Tw.mx_auto
                    , Bp.lg
                        [ Tw.py_16
                        , Tw.max_w_none
                        , Tw.mx_0
                        , Tw.px_0
                        ]
                    , Bp.sm
                        [ Tw.px_6
                        ]
                    ]
                ]
                [ div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.bg_gradient_to_r
                                , Tw.from_blue_600
                                , Tw.to_blue_700
                                ]
                            ]
                            [ svg
                                [ SvgAttr.css
                                    [ Tw.h_6
                                    , Tw.w_6
                                    , Tw.text_white
                                    ]
                                , SvgAttr.fill "none"
                                , SvgAttr.viewBox "0 0 24 24"
                                , SvgAttr.stroke "currentColor"
                                , Attr.attribute "aria-hidden" "true"
                                ]
                                [ path
                                    [ SvgAttr.strokeLinecap "round"
                                    , SvgAttr.strokeLinejoin "round"
                                    , SvgAttr.strokeWidth "2"
                                    , SvgAttr.d info.svgIcon
                                    ]
                                    []
                                ]
                            ]
                        ]
                    , div
                        [ css
                            [ Tw.mt_6
                            ]
                        ]
                        [ h2
                            [ css
                                [ Tw.text_3xl
                                , Tw.font_extrabold
                                , Tw.tracking_tight
                                , Tw.text_gray_900
                                ]
                            ]
                            [ text info.heading ]
                        , p
                            [ css
                                [ Tw.mt_4
                                , Tw.text_lg
                                , Tw.text_gray_500
                                ]
                            ]
                            [ text info.body ]
                        , div
                            [ css
                                [ Tw.mt_6
                                ]
                            ]
                            [ Link.link info.buttonLink
                                [ css
                                    [ Tw.inline_flex
                                    , Tw.px_4
                                    , Tw.py_2
                                    , Tw.border
                                    , Tw.border_transparent
                                    , Tw.text_base
                                    , Tw.font_medium
                                    , Tw.rounded_md
                                    , Tw.shadow_sm
                                    , Tw.text_white
                                    , Tw.bg_gradient_to_r
                                    , Tw.from_blue_600
                                    , Tw.to_blue_700
                                    , Css.hover
                                        [ Tw.from_blue_700
                                        , Tw.to_blue_800
                                        ]
                                    ]
                                ]
                                [ text info.buttonText ]
                            ]
                        ]
                    ]
                ]
            , div
                [ css
                    [ Tw.mt_12
                    , Bp.lg
                        [ Tw.mt_0
                        ]
                    , Bp.sm
                        [ Tw.mt_16
                        ]
                    ]
                ]
                [ div
                    [ css
                        [ Tw.pl_4
                        , Tw.neg_mr_48
                        , Tw.pb_12
                        , Bp.lg
                            [ Tw.px_0
                            , Tw.m_0
                            , Tw.relative
                            , Tw.h_full
                            ]
                        , Bp.md
                            [ Tw.neg_mr_16
                            ]
                        , Bp.sm
                            [ Tw.pl_6
                            ]
                        ]
                    ]
                    [ CodeTab.view info.code
                    ]
                ]
            ]
        ]
