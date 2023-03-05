module View.Header exposing (..)

import Css
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Html.Styled.Events
import Path exposing (Path)
import Svg.Styled exposing (path, svg)
import Svg.Styled.Attributes as SvgAttr
import Tailwind.Breakpoints as Bp
import Tailwind.Theme as Theme
import Tailwind.Utilities as Tw


view : msg -> Int -> Path -> Html msg
view toggleMobileMenuMsg stars currentPath =
    nav
        [ css
            [ Tw.flex
            , Tw.items_center
            , Tw.bg_color Theme.white
            , Tw.z_20
            , Tw.sticky
            , Tw.top_0
            , Tw.left_0
            , Tw.right_0
            , Tw.h_16
            , Tw.border_b
            , Tw.border_color Theme.gray_200
            , Tw.px_6

            --, Bp.dark
            --    [ Tw.bg_dark
            --    , Tw.border_gray_900
            --    ]
            ]
        ]
        [ div
            [ css
                [ Tw.hidden
                , Tw.w_full
                , Tw.flex
                , Tw.items_center
                , Bp.md
                    [ Tw.block
                    ]
                ]
            ]
            [ a
                [ css
                    [ Tw.no_underline
                    , Tw.text_color Theme.current
                    , Tw.flex
                    , Tw.items_center
                    , Css.hover
                        [ Tw.opacity_75
                        ]
                    ]
                , Attr.href "/"
                ]
                [ span
                    [ css
                        [ Tw.mr_0
                        , Tw.neg_ml_2
                        , Tw.font_extrabold
                        , Tw.inline
                        , Bp.md
                            [ Tw.inline
                            ]
                        ]
                    ]
                    [ text "elm-pages" ]
                ]
            ]
        , headerLink currentPath "showcase" "Showcase"
        , headerLink currentPath "blog" "Blog"
        , span
            [ css
                [ Tw.hidden
                , Bp.md
                    [ Tw.inline
                    ]
                ]
            ]
            [ headerLink currentPath "docs" "Docs" ]
        , button
            [ Attr.type_ "button"
            , Html.Styled.Events.onClick toggleMobileMenuMsg
            , css
                [ Tw.flex
                , Tw.items_center
                , Tw.px_1
                , Tw.border
                , Tw.border_color Theme.gray_300
                , Tw.shadow_sm
                , Tw.text_sm
                , Tw.rounded_md
                , Tw.text_color Theme.gray_700
                , Tw.bg_color Theme.white
                , Bp.md [ Tw.hidden ]
                , Css.focus
                    [ Tw.outline_none
                    , Tw.ring_2
                    , Tw.ring_offset_2
                    , Tw.ring_color Theme.blue_500
                    ]
                , Css.hover
                    [ Tw.bg_color Theme.gray_50
                    ]
                ]
            ]
            [ linkInner currentPath "docs" "Docs"
            , svg
                [ SvgAttr.css
                    [ Tw.h_5
                    , Tw.w_5
                    ]
                , SvgAttr.viewBox "0 0 20 20"
                , SvgAttr.fill "currentColor"
                ]
                [ path
                    [ SvgAttr.fillRule "evenodd"
                    , SvgAttr.d "M3 5a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM3 10a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM3 15a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1z"
                    , SvgAttr.clipRule "evenodd"
                    ]
                    []
                ]
            ]
        , div
            [ css
                [ Tw.neg_mr_2
                ]
            ]
            []
        ]


headerLink : Path -> String -> String -> Html msg
headerLink currentPagePath linkTo name =
    a
        [ Attr.href ("/" ++ linkTo)
        , Attr.attribute "elm-pages:prefetch" "true"
        ]
        [ linkInner currentPagePath linkTo name ]


linkInner : Path -> String -> String -> Html msg
linkInner currentPagePath linkTo name =
    let
        isCurrentPath : Bool
        isCurrentPath =
            List.head currentPagePath == Just linkTo
    in
    span
        [ css
            [ Tw.text_sm
            , Tw.p_2
            , if isCurrentPath then
                Css.batch
                    [ Tw.text_color Theme.blue_600
                    , Css.hover
                        [ Tw.text_color Theme.blue_700
                        ]
                    ]

              else
                Css.batch
                    [ Tw.text_color Theme.gray_600
                    , Css.hover
                        [ Tw.text_color Theme.gray_900
                        ]
                    ]
            ]
        ]
        [ text name ]
