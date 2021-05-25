module Page.Blog exposing (Data, Model, Msg, page)

import Article
import DataSource
import Date
import Head
import Head.Seo as Seo
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Page exposing (Page, PageWithState, StaticPayload)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route exposing (Route)
import Shared
import SiteOld
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import View exposing (View)


type alias Msg =
    Never


page : Page RouteParams Data
page =
    Page.singleRoute
        { head = head
        , data = data
        }
        |> Page.buildNoState
            { view = view
            }


data : DataSource.DataSource Data
data =
    Article.allMetadata


type alias Data =
    List ( Route, Article.ArticleMetadata )


type alias RouteParams =
    {}


type alias Model =
    ()


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data {}
    -> View msg
view maybeUrl sharedModel staticPayload =
    { title = "elm-pages blog"
    , body =
        [ div
            [ css
                [ Tw.relative
                , Tw.bg_gray_100
                , Tw.min_h_screen
                , Tw.pt_32
                , Tw.pb_20
                , Tw.px_4
                , Bp.lg
                    [ Tw.pt_24
                    , Tw.pb_28
                    , Tw.px_8
                    ]
                , Bp.sm
                    [ Tw.px_6
                    ]
                ]
            ]
            [ div
                [ css
                    [ Tw.absolute
                    , Tw.inset_0
                    ]
                ]
                [ div
                    [ css
                        [ Tw.h_1over3
                        , Bp.sm
                            [ Tw.h_2over3
                            ]
                        ]
                    ]
                    []
                ]
            , div
                [ css
                    [ Tw.relative
                    , Tw.max_w_7xl
                    , Tw.mx_auto
                    ]
                ]
                [ div
                    [ css
                        [ Tw.text_center
                        ]
                    ]
                    [ h2
                        [ css
                            [ Tw.text_3xl
                            , Tw.tracking_tight
                            , Tw.font_extrabold
                            , Tw.text_gray_900
                            , Bp.sm
                                [ Tw.text_4xl
                                ]
                            ]
                        ]
                        [ text "Blog" ]
                    , p
                        [ css
                            [ Tw.mt_3
                            , Tw.max_w_2xl
                            , Tw.mx_auto
                            , Tw.text_xl
                            , Tw.text_gray_500
                            , Bp.sm
                                [ Tw.mt_4
                                ]
                            ]
                        ]
                        [ text "The latest elm-pages news and articles." ]
                    ]
                , div
                    [ css
                        [ Tw.mt_12
                        , Tw.max_w_lg
                        , Tw.mx_auto
                        , Tw.grid
                        , Tw.gap_5
                        , Bp.lg
                            [ Tw.grid_cols_3
                            , Tw.max_w_none
                            ]
                        ]
                    ]
                    (staticPayload.data
                        |> List.map
                            (\articleInfo ->
                                blogCard articleInfo
                            )
                    )
                ]
            ]
        ]
    }


head : StaticPayload Data {} -> List Head.Tag
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
        , description = SiteOld.tagline
        , locale = Nothing
        , title = "elm-pages blog"
        }
        |> Seo.website


link : Route.Route -> List (Attribute msg) -> List (Html msg) -> Html msg
link route attrs children =
    Route.toLink
        (\anchorAttrs ->
            a
                (List.map Attr.fromUnstyled anchorAttrs ++ attrs)
                children
        )
        route


blogCard : ( Route, Article.ArticleMetadata ) -> Html msg
blogCard ( route, info ) =
    link route
        [ css
            [ Tw.flex
            , Tw.flex_col
            , Tw.rounded_lg
            , Tw.shadow_lg
            , Tw.overflow_hidden
            ]
        ]
        [ div
            [ css
                [ Tw.flex_1
                , Tw.bg_white
                , Tw.p_6
                , Tw.flex
                , Tw.flex_col
                , Tw.justify_between
                ]
            ]
            [ div
                [ css
                    [ Tw.flex_1
                    ]
                ]
                [ span
                    [ css
                        [ Tw.block
                        , Tw.mt_2
                        ]
                    ]
                    [ p
                        [ css
                            [ Tw.text_xl
                            , Tw.font_semibold
                            , Tw.text_gray_900
                            ]
                        ]
                        [ text info.title ]
                    , p
                        [ css
                            [ Tw.mt_3
                            , Tw.text_base
                            , Tw.text_gray_500
                            ]
                        ]
                        [ text info.description ]
                    ]
                ]
            , div
                [ css
                    [ Tw.mt_6
                    , Tw.flex
                    , Tw.items_center
                    ]
                ]
                [ div
                    []
                    [ div
                        [ css
                            [ Tw.flex
                            , Tw.space_x_1
                            , Tw.text_sm
                            , Tw.text_gray_400
                            ]
                        ]
                        [ time
                            [ Attr.datetime "2020-03-16"
                            ]
                            [ text (info.published |> Date.format "MMMM ddd, yyyy") ]
                        ]
                    ]
                ]
            ]
        ]
