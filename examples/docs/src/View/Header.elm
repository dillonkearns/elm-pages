module View.Header exposing (..)

import Css
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Html.Styled.Events
import Pages.PagePath as PagePath exposing (PagePath)
import Svg.Styled exposing (svg)
import Svg.Styled.Attributes as SvgAttr
import Tailwind.Breakpoints as Bp
import Tailwind.Utilities as Tw


view : msg -> Int -> PagePath -> Html msg
view toggleMobileMenuMsg stars currentPath =
    nav
        [ css
            [ Tw.flex
            , Tw.items_center
            , Tw.bg_white
            , Tw.z_20
            , Tw.fixed
            , Tw.top_0
            , Tw.left_0
            , Tw.right_0
            , Tw.h_16
            , Tw.border_b
            , Tw.border_gray_200
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
                    , Tw.text_current
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
        , headerLink currentPath [ "showcase" ] "Showcase"
        , headerLink currentPath [ "blog" ] "Blog"
        , span
            [ css
                [ Tw.hidden
                , Bp.md
                    [ Tw.inline
                    ]
                ]
            ]
            [ headerLink currentPath [ "docs" ] "Docs" ]
        , button
            [ Attr.type_ "button"
            , Html.Styled.Events.onClick toggleMobileMenuMsg
            , css
                [ Tw.flex
                , Tw.items_center
                , Tw.px_1
                , Tw.border
                , Tw.border_gray_300
                , Tw.shadow_sm
                , Tw.text_sm
                , Tw.rounded_md
                , Tw.text_gray_700
                , Tw.bg_white
                , Css.focus
                    [ Tw.outline_none
                    , Tw.ring_2
                    , Tw.ring_offset_2
                    , Tw.ring_blue_500
                    ]
                , Css.hover
                    [ Tw.bg_gray_50
                    ]
                ]
            ]
            [ linkInner currentPath [ "docs" ] "Docs"
            , svg
                [ SvgAttr.fill "none"
                , SvgAttr.width "24"
                , SvgAttr.height "24"
                , SvgAttr.viewBox "0 0 24 24"
                , SvgAttr.stroke "rgba(0,0,0,0.75)"
                ]
                [ Svg.Styled.path
                    [ SvgAttr.strokeLinecap "round"
                    , SvgAttr.strokeLinejoin "round"
                    , SvgAttr.strokeWidth "2"
                    , SvgAttr.d "M4 6h16M4 12h16M4 18h16"
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


headerLink : PagePath -> List String -> String -> Html msg
headerLink currentPagePath linkTo name =
    let
        isCurrentPath =
            currentPath == List.take (List.length currentPath) linkTo

        currentPath =
            PagePath.toPath currentPagePath
    in
    a
        [ css
            [ Tw.text_sm
            , Tw.p_2
            , if isCurrentPath then
                Tw.text_blue_500

              else
                Tw.text_gray_700
            ]
        , Attr.href (linkTo |> String.join "/")
        ]
        [ text name ]


linkInner : PagePath -> List String -> String -> Html msg
linkInner currentPagePath linkTo name =
    let
        isCurrentPath =
            currentPath == List.take (List.length currentPath) linkTo

        currentPath =
            PagePath.toPath currentPagePath
    in
    span
        [ css
            [ Tw.text_sm
            , Tw.p_2
            , if isCurrentPath then
                Tw.text_blue_500

              else
                Tw.text_gray_700
            ]
        ]
        [ text name ]
