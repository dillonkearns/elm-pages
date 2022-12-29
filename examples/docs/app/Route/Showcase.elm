module Route.Showcase exposing (ActionData, Data, Model, Msg, route)

import Css
import DataSource exposing (DataSource)
import Exception exposing (Catchable, Throwable)
import Head
import Head.Seo as Seo
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, href)
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import RouteBuilder exposing (StatefulRoute, StaticPayload)
import Shared
import Showcase
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : DataSource Throwable Data
data =
    Showcase.staticRequest


type alias Data =
    List Showcase.Entry


type alias ActionData =
    {}


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData {}
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel static =
    { title = "elm-pages blog"
    , body =
        [ div
            [ css
                [ Tw.flex
                , Tw.flex_col
                , Tw.pt_8
                , Tw.px_4
                , Bp.lg
                    [ Tw.px_8
                    ]
                , Bp.sm
                    [ Tw.py_20
                    , Tw.px_6
                    ]
                ]
            ]
            [ topSection
            , div
                [ css
                    [ Tw.pt_8
                    , Tw.flex
                    , Tw.justify_around
                    ]
                ]
                [ showcaseEntries static.data ]
            ]
        ]
    }


head : StaticPayload Data ActionData {} -> List Head.Tag
head staticPayload =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = [ "images", "icon-png.png" ] |> Path.join |> Pages.Url.fromPath
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "See some neat sites built using elm-pages! (Or submit yours!)"
        , locale = Nothing
        , title = "elm-pages sites showcase"
        }
        |> Seo.website


showcaseEntries : List Showcase.Entry -> Html msg
showcaseEntries items =
    ul
        [ Attr.attribute "role" "list"
        , css
            [ Tw.grid
            , Tw.grid_cols_2
            , Tw.gap_x_4
            , Tw.gap_y_8
            , Tw.w_full
            , Tw.max_w_screen_lg

            --, Bp.lg
            --    [ Tw.grid_cols_4
            --    ]
            , Bp.sm
                [ Tw.grid_cols_3
                , Tw.gap_x_6
                ]
            , Bp.xl
                [ Tw.gap_x_8
                ]
            ]
        ]
        (items
            |> List.map showcaseItem
        )


showcaseItem : Showcase.Entry -> Html msg
showcaseItem item =
    li
        [ css
            [ Tw.relative
            ]
        ]
        [ div
            [ css
                [ --Tw.group
                  Tw.block

                --, Tw.w_full
                , Tw.aspect_w_10
                , Tw.aspect_h_7
                , Tw.rounded_lg
                , Tw.bg_gray_100
                , Tw.overflow_hidden

                --, Bp.focus-within
                --    [ Tw.ring_2
                --    , Tw.ring_offset_2
                --    , Tw.ring_offset_gray_100
                --    , Tw.ring_indigo_500
                --    ]
                ]
            ]
            [ a
                [ href item.liveUrl
                , Attr.target "_blank"
                , Attr.rel "noopener"
                ]
                [ img
                    [ Attr.src <| "https://image.thum.io/get/width/800/crop/800/" ++ item.screenshotUrl
                    , Attr.alt ""
                    , Attr.attribute "loading" "lazy"
                    , css
                        [ Tw.object_cover
                        , Tw.pointer_events_none

                        --, Bp.group
                        --- hover
                        --    [ Tw.opacity_75
                        --    ]
                        ]
                    ]
                    []
                ]

            --, button
            --    [ Attr.type_ "button"
            --    , css
            --        [ Tw.absolute
            --        , Tw.inset_0
            --        , Css.focus
            --            [ Tw.outline_none
            --            ]
            --        ]
            --    ]
            --    [ span
            --        [ css
            --            [ Tw.sr_only
            --            ]
            --        ]
            --        [ text "View details for IMG_4985.HEIC" ]
            --    ]
            ]
        , a
            [ href item.liveUrl
            , Attr.target "_blank"
            , Attr.rel "noopener"
            , css
                [ Tw.mt_2
                , Tw.block
                , Tw.text_sm
                , Tw.font_medium
                , Tw.text_gray_900
                , Tw.truncate

                --, Tw.pointer_events_none
                ]
            ]
            [ text item.displayName ]
        , a
            [ href item.authorUrl
            , Attr.target "_blank"
            , Attr.rel "noopener"
            , css
                [ Tw.block
                , Tw.text_sm
                , Tw.font_medium
                , Tw.text_gray_500

                --, Tw.pointer_events_none
                ]
            ]
            [ text item.authorName ]
        ]


topSection : Html msg
topSection =
    div
        [ css
            []
        ]
        [ div
            [ css
                [ Tw.max_w_2xl
                , Tw.mx_auto
                , Tw.text_center
                , Tw.py_16
                , Bp.sm
                    [ Tw.py_20
                    ]
                ]
            ]
            [ h2
                [ css
                    [ Tw.text_3xl
                    , Tw.font_extrabold
                    , Bp.sm
                        [ Tw.text_4xl
                        ]
                    ]
                ]
                [ span
                    [ css
                        [ Tw.block
                        ]
                    ]
                    [ text "elm-pages Showcase" ]
                ]
            , p
                [ css
                    [ Tw.mt_4
                    , Tw.text_lg
                    , Tw.leading_6
                    , Tw.text_gray_500
                    ]
                ]
                [ text "Check out some projects from the elm-pages community." ]
            , a
                [ Attr.href "https://airtable.com/shrPSenIW2EQqJ083"
                , Attr.target "_blank"
                , Attr.rel "noopener"
                , css
                    [ Tw.mt_8
                    , Tw.w_full
                    , Tw.inline_flex
                    , Tw.items_center
                    , Tw.justify_center
                    , Tw.px_5
                    , Tw.py_3
                    , Tw.border
                    , Tw.border_transparent
                    , Tw.text_white
                    , Tw.font_medium
                    , Tw.rounded_md
                    , Tw.bg_blue_800
                    , Css.hover
                        [ Tw.bg_blue_600
                        ]
                    , Bp.sm
                        [ Tw.w_auto
                        ]
                    ]
                ]
                [ text "Submit your site to the showcase" ]
            ]
        ]
