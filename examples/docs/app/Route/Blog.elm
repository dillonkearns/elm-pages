module Route.Blog exposing (ActionData, Data, Model, Msg, route)

import Article
import BackendTask exposing (BackendTask)
import BuildError exposing (BuildError)
import Date
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route exposing (Route)
import RouteBuilder exposing (StatelessRoute, StaticPayload)
import Shared
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw
import View exposing (View)


type alias Msg =
    ()


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState
            { view = view
            }


data : BackendTask FatalError Data
data =
    Article.allMetadata
        |> BackendTask.allowFatal


type alias Data =
    List ( Route, Article.ArticleMetadata )


type alias ActionData =
    {}


type alias RouteParams =
    {}


type alias Model =
    {}


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData {}
    -> View msg
view maybeUrl sharedModel staticPayload =
    { title = "elm-pages blog"
    , body =
        [ div
            [ css
                [ Tw.relative
                , Tw.bg_gray_100
                , Tw.min_h_screen
                , Tw.pt_16
                , Tw.pb_20
                , Tw.px_4
                , Bp.lg
                    [ Tw.pt_16
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
                        [ text blogDescription ]
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


head : StaticPayload Data ActionData RouteParams -> List Head.Tag
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
        , description = blogDescription
        , locale = Nothing
        , title = "elm-pages blog"
        }
        |> Seo.website


link : Route.Route -> List (Attribute msg) -> List (Html msg) -> Html msg
link route_ attrs children =
    Route.toLink
        (\anchorAttrs ->
            a
                (List.map Attr.fromUnstyled anchorAttrs ++ attrs)
                children
        )
        route_


blogCard : ( Route, Article.ArticleMetadata ) -> Html msg
blogCard ( route_, info ) =
    link route_
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


blogDescription : String
blogDescription =
    "The latest elm-pages news and articles."
