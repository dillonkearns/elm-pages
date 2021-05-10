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
        , headerLink currentPath [ "docs" ] "Docs"
        , a
            [ css
                [ Tw.text_current
                , Tw.p_2
                ]
            , Attr.href "https://github.com/dillonkearns/elm-pages"
            , Attr.target "_blank"
            ]
            [ svg
                [ SvgAttr.height "24"
                , SvgAttr.viewBox "2 2 20 20"
                , SvgAttr.fill "none"
                ]
                [ Svg.Styled.path
                    [ SvgAttr.fillRule "evenodd"
                    , SvgAttr.clipRule "evenodd"
                    , SvgAttr.d "M12 3C7.0275 3 3 7.12937 3 12.2276C3 16.3109 5.57625 19.7597 9.15374 20.9824C9.60374 21.0631 9.77249 20.7863 9.77249 20.5441C9.77249 20.3249 9.76125 19.5982 9.76125 18.8254C7.5 19.2522 6.915 18.2602 6.735 17.7412C6.63375 17.4759 6.19499 16.6569 5.8125 16.4378C5.4975 16.2647 5.0475 15.838 5.80124 15.8264C6.51 15.8149 7.01625 16.4954 7.18499 16.7723C7.99499 18.1679 9.28875 17.7758 9.80625 17.5335C9.885 16.9337 10.1212 16.53 10.38 16.2993C8.3775 16.0687 6.285 15.2728 6.285 11.7432C6.285 10.7397 6.63375 9.9092 7.20749 9.26326C7.1175 9.03257 6.8025 8.08674 7.2975 6.81794C7.2975 6.81794 8.05125 6.57571 9.77249 7.76377C10.4925 7.55615 11.2575 7.45234 12.0225 7.45234C12.7875 7.45234 13.5525 7.55615 14.2725 7.76377C15.9937 6.56418 16.7475 6.81794 16.7475 6.81794C17.2424 8.08674 16.9275 9.03257 16.8375 9.26326C17.4113 9.9092 17.76 10.7281 17.76 11.7432C17.76 15.2843 15.6563 16.0687 13.6537 16.2993C13.98 16.5877 14.2613 17.1414 14.2613 18.0065C14.2613 19.2407 14.25 20.2326 14.25 20.5441C14.25 20.7863 14.4188 21.0746 14.8688 20.9824C16.6554 20.364 18.2079 19.1866 19.3078 17.6162C20.4077 16.0457 20.9995 14.1611 21 12.2276C21 7.12937 16.9725 3 12 3Z"
                    , SvgAttr.fill "currentColor"
                    ]
                    []
                ]
            ]
        , button
            [ Html.Styled.Events.onClick toggleMobileMenuMsg
            , css
                [ Tw.block
                , Tw.p_2
                , Bp.md
                    [ Tw.hidden
                    ]
                ]
            ]
            [ svg
                [ SvgAttr.fill "none"
                , SvgAttr.width "24"
                , SvgAttr.height "24"
                , SvgAttr.viewBox "0 0 24 24"
                , SvgAttr.stroke "currentColor"
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
            [ Tw.text_current
            , Tw.text_sm
            , Tw.p_2
            , if isCurrentPath then
                Tw.text_blue_500

              else
                Css.batch []
            ]
        , Attr.href (linkTo |> String.join "/")
        ]
        [ text name ]
