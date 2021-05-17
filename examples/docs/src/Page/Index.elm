module Page.Index exposing (Data, Model, Msg, page)

import Css
import DataSource exposing (DataSource)
import Document exposing (Document)
import Head
import Head.Seo as Seo
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Link
import Page exposing (Page, StaticPayload)
import Pages.ImagePath as ImagePath
import Route exposing (Route)
import SiteOld
import Svg.Styled exposing (path, svg)
import Svg.Styled.Attributes as SvgAttr
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import View.CodeTab as CodeTab



{-
   example : String -> String -> DataSourceString
   example bandName songName =
       DataSource.Http.get
           (Secrets.succeed
               (Url.Builder.absolute
                   [ "https://private-anon-bc5d0d71a9-lyricsovh.apiary-proxy.com"
                   , "v1"
                   , bandName
                   , songName
                   ]
                   []
               )
           )
           (Decode.field "lyrics" Decode.string)

-}


type alias Model =
    ()


type alias Msg =
    Never


type alias RouteParams =
    {}


type alias Data =
    ()


page : Page RouteParams Data
page =
    Page.singleRoute
        { head = head
        , data = data
        }
        |> Page.buildNoState { view = view }


head :
    StaticPayload Data RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = ImagePath.build [ "images", "icon-png.png" ]
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    { title = "elm-pages - a statically typed site generator" -- metadata.title -- TODO
    , body =
        [ landingView
        , gradientFeatures
        ]
            |> Document.ElmCssView
    }


data : DataSource Data
data =
    DataSource.succeed ()


landingView =
    div
        [ css
            [ Tw.relative
            , Tw.pt_32
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
            , body = "Whether your data is coming from markdown files, APIs, a CMS, or all at once, elm-pages lets you pull in just the data you need for a page."
            , buttonText = "Check out the Docs"
            , buttonLink = Route.Docs__Section__ { section = Nothing }
            , code =
                ( "Page.Repo.Name_.elm", """module Page.Repo.Name_ exposing (Data, Model, Msg, page)
                
type alias Data = Int
type alias RouteParams = { name : String }

page : Page RouteParams Data
page =
    Page.prerenderedRoute
        { head = head
        , routes = routes
        , data = data
        }
        |> Page.buildNoState { view = view }

routes : DataSource (List RouteParams)
routes =
    DataSource.succeed [ { name = "elm-pages" } ]

data : RouteParams -> DataSource Data
data routeParams =
    DataSource.Http.get
        (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages")
        (Decode.field "stargazer_count" Decode.int)

view :
    StaticPayload Data RouteParams
    -> Document Msg
view static =
    { title = static.routeParams.name
    , body =
        [ h1 [] [ text static.routeParams.name ]
        , p [] [ text ("Stars: " ++ String.fromInt static.data) ]
        ]
    }""" )
            }
        , div
            [ css
                [ Tw.mt_24
                ]
            ]
            [ div
                [ css
                    [ Bp.lg
                        [ Tw.mx_auto
                        , Tw.max_w_7xl
                        , Tw.px_8
                        , Tw.grid
                        , Tw.grid_cols_2
                        , Tw.grid_flow_col_dense
                        , Tw.gap_24
                        ]
                    ]
                ]
                [ div
                    [ css
                        [ Tw.px_4
                        , Tw.max_w_xl
                        , Tw.mx_auto
                        , Bp.lg
                            [ Tw.py_32
                            , Tw.max_w_none
                            , Tw.mx_0
                            , Tw.px_0
                            , Tw.col_start_2
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
                                    , Tw.from_purple_600
                                    , Tw.to_indigo_600
                                    ]
                                ]
                                [ {- Heroicon name: outline/sparkles -}
                                  svg
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
                                        , SvgAttr.d "M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z"
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
                                [ text "Better understand your customers" ]
                            , p
                                [ css
                                    [ Tw.mt_4
                                    , Tw.text_lg
                                    , Tw.text_gray_500
                                    ]
                                ]
                                [ text "Semper curabitur ullamcorper posuere nunc sed. Ornare iaculis bibendum malesuada faucibus lacinia porttitor. Pulvinar laoreet sagittis viverra duis. In venenatis sem arcu pretium pharetra at. Lectus viverra dui tellus ornare pharetra." ]
                            , div
                                [ css
                                    [ Tw.mt_6
                                    ]
                                ]
                                [ a
                                    [ Attr.href "#"
                                    , css
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
                                        , Tw.from_purple_600
                                        , Tw.to_indigo_600
                                        , Css.hover
                                            [ Tw.from_purple_700
                                            , Tw.to_indigo_700
                                            ]
                                        ]
                                    ]
                                    [ text "Get started" ]
                                ]
                            ]
                        ]
                    ]
                , div
                    [ css
                        [ Tw.mt_12
                        , Bp.lg
                            [ Tw.mt_0
                            , Tw.col_start_1
                            ]
                        , Bp.sm
                            [ Tw.mt_16
                            ]
                        ]
                    ]
                    [ div
                        [ css
                            [ Tw.pr_4
                            , Tw.neg_ml_48
                            , Bp.lg
                                [ Tw.px_0
                                , Tw.m_0
                                , Tw.relative
                                , Tw.h_full
                                ]
                            , Bp.md
                                [ Tw.neg_ml_16
                                ]
                            , Bp.sm
                                [ Tw.pr_6
                                ]
                            ]
                        ]
                        [ img
                            [ css
                                [ Tw.w_full
                                , Tw.rounded_xl
                                , Tw.shadow_xl
                                , Tw.ring_1
                                , Tw.ring_black
                                , Tw.ring_opacity_5
                                , Bp.lg
                                    [ Tw.absolute
                                    , Tw.right_0
                                    , Tw.h_full
                                    , Tw.w_auto
                                    , Tw.max_w_none
                                    ]
                                ]
                            , Attr.src "https://tailwindui.com/img/component-images/inbox-app-screenshot-2.jpg"
                            , Attr.alt "Customer profile user interface"
                            ]
                            []
                        ]
                    ]
                ]
            ]
        ]



{- Gradient Feature Section -}


gradientFeatures =
    div
        [ css
            [ Tw.bg_gradient_to_r

            --, Tw.from_purple_800
            --, Tw.to_indigo_700
            , Tw.from_blue_800
            , Tw.to_blue_900
            ]
        ]
        [ div
            [ css
                [ Tw.max_w_4xl
                , Tw.mx_auto
                , Tw.px_4
                , Tw.py_16
                , Bp.lg
                    [ Tw.max_w_7xl
                    , Tw.pt_24
                    , Tw.px_8
                    ]
                , Bp.sm
                    [ Tw.px_6
                    , Tw.pt_20
                    , Tw.pb_24
                    ]
                ]
            ]
            [ h2
                [ css
                    [ Tw.text_3xl
                    , Tw.font_extrabold
                    , Tw.text_white
                    , Tw.tracking_tight
                    ]
                ]
                [ text "Inbox support built for efficiency" ]
            , p
                [ css
                    [ Tw.mt_4
                    , Tw.max_w_3xl
                    , Tw.text_lg
                    , Tw.text_purple_200
                    ]
                ]
                [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis. Blandit aliquam sit nisl euismod mattis in." ]
            , div
                [ css
                    [ Tw.mt_12
                    , Tw.grid
                    , Tw.grid_cols_1
                    , Tw.gap_x_6
                    , Tw.gap_y_12
                    , Bp.lg
                        [ Tw.mt_16
                        , Tw.grid_cols_4
                        , Tw.gap_x_8
                        , Tw.gap_y_16
                        ]
                    , Bp.sm
                        [ Tw.grid_cols_2
                        ]
                    ]
                ]
                [ div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.bg_white
                                , Tw.bg_opacity_10
                                ]
                            ]
                            [ {- Heroicon name: outline/inbox -}
                              svg
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
                                    , SvgAttr.d "M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
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
                        [ h3
                            [ css
                                [ Tw.text_lg
                                , Tw.font_medium
                                , Tw.text_white
                                ]
                            ]
                            [ text "Unlimited Inboxes" ]
                        , p
                            [ css
                                [ Tw.mt_2
                                , Tw.text_base
                                , Tw.text_purple_200
                                ]
                            ]
                            [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis." ]
                        ]
                    ]
                , div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.bg_white
                                , Tw.bg_opacity_10
                                ]
                            ]
                            [ {- Heroicon name: outline/users -}
                              svg
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
                                    , SvgAttr.d "M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
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
                        [ h3
                            [ css
                                [ Tw.text_lg
                                , Tw.font_medium
                                , Tw.text_white
                                ]
                            ]
                            [ text "Manage Team Members" ]
                        , p
                            [ css
                                [ Tw.mt_2
                                , Tw.text_base
                                , Tw.text_purple_200
                                ]
                            ]
                            [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis." ]
                        ]
                    ]
                , div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.bg_white
                                , Tw.bg_opacity_10
                                ]
                            ]
                            [ {- Heroicon name: outline/trash -}
                              svg
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
                                    , SvgAttr.d "M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
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
                        [ h3
                            [ css
                                [ Tw.text_lg
                                , Tw.font_medium
                                , Tw.text_white
                                ]
                            ]
                            [ text "Spam Report" ]
                        , p
                            [ css
                                [ Tw.mt_2
                                , Tw.text_base
                                , Tw.text_purple_200
                                ]
                            ]
                            [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis." ]
                        ]
                    ]
                , div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.bg_white
                                , Tw.bg_opacity_10
                                ]
                            ]
                            [ {- Heroicon name: outline/pencil-alt -}
                              svg
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
                                    , SvgAttr.d "M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
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
                        [ h3
                            [ css
                                [ Tw.text_lg
                                , Tw.font_medium
                                , Tw.text_white
                                ]
                            ]
                            [ text "Compose in Markdown" ]
                        , p
                            [ css
                                [ Tw.mt_2
                                , Tw.text_base
                                , Tw.text_purple_200
                                ]
                            ]
                            [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis." ]
                        ]
                    ]
                , div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.bg_white
                                , Tw.bg_opacity_10
                                ]
                            ]
                            [ {- Heroicon name: outline/document-report -}
                              svg
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
                                    , SvgAttr.d "M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
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
                        [ h3
                            [ css
                                [ Tw.text_lg
                                , Tw.font_medium
                                , Tw.text_white
                                ]
                            ]
                            [ text "Team Reporting" ]
                        , p
                            [ css
                                [ Tw.mt_2
                                , Tw.text_base
                                , Tw.text_purple_200
                                ]
                            ]
                            [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis." ]
                        ]
                    ]
                , div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.bg_white
                                , Tw.bg_opacity_10
                                ]
                            ]
                            [ {- Heroicon name: outline/reply -}
                              svg
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
                                    , SvgAttr.d "M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"
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
                        [ h3
                            [ css
                                [ Tw.text_lg
                                , Tw.font_medium
                                , Tw.text_white
                                ]
                            ]
                            [ text "Saved Replies" ]
                        , p
                            [ css
                                [ Tw.mt_2
                                , Tw.text_base
                                , Tw.text_purple_200
                                ]
                            ]
                            [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis." ]
                        ]
                    ]
                , div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.bg_white
                                , Tw.bg_opacity_10
                                ]
                            ]
                            [ {- Heroicon name: outline/chat-alt -}
                              svg
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
                                    , SvgAttr.d "M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z"
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
                        [ h3
                            [ css
                                [ Tw.text_lg
                                , Tw.font_medium
                                , Tw.text_white
                                ]
                            ]
                            [ text "Email Commenting" ]
                        , p
                            [ css
                                [ Tw.mt_2
                                , Tw.text_base
                                , Tw.text_purple_200
                                ]
                            ]
                            [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis." ]
                        ]
                    ]
                , div []
                    [ div []
                        [ span
                            [ css
                                [ Tw.flex
                                , Tw.items_center
                                , Tw.justify_center
                                , Tw.h_12
                                , Tw.w_12
                                , Tw.rounded_md
                                , Tw.bg_white
                                , Tw.bg_opacity_10
                                ]
                            ]
                            [ {- Heroicon name: outline/heart -}
                              svg
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
                                    , SvgAttr.d "M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
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
                        [ h3
                            [ css
                                [ Tw.text_lg
                                , Tw.font_medium
                                , Tw.text_white
                                ]
                            ]
                            [ text "Connect with Customers" ]
                        , p
                            [ css
                                [ Tw.mt_2
                                , Tw.text_base
                                , Tw.text_purple_200
                                ]
                            ]
                            [ text "Ac tincidunt sapien vehicula erat auctor pellentesque rhoncus. Et magna sit morbi lobortis." ]
                        ]
                    ]
                ]
            ]
        ]


firstSection :
    { heading : String
    , body : String
    , buttonLink : Route
    , buttonText : String
    , code : ( String, String )
    }
    -> Html Never
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
                                    , SvgAttr.d "M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"
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
