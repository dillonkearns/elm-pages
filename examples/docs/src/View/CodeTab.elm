module View.CodeTab exposing (view)

import Css
import Html.Styled as Html exposing (..)
import Html.Styled.Attributes as Attr exposing (..)
import SyntaxHighlight
import Tailwind.Theme as Theme
import Tailwind.Utilities as Tw


view : ( String, String ) -> Html msg
view tab =
    div
        [ css
            [ Tw.rounded_xl
            , Tw.shadow_2xl
            , Tw.bg_color Theme.black
            , Tw.rounded_lg
            , Tw.shadow_lg
            ]
        ]
        [ iconArea
        , codeTabs tab
        , elmCodeBlock (Tuple.second tab)
        ]


iconArea : Html msg
iconArea =
    div
        [ css
            [ Tw.flex_none
            , Tw.items_center
            , Tw.flex
            , Tw.h_11
            , Tw.px_4
            ]
        ]
        [ div [ css [ Tw.flex, Tw.space_x_1_dot_5 ] ]
            [ div
                [ css
                    [ Tw.w_3
                    , Tw.h_3
                    , Tw.border_2
                    , Tw.rounded_full
                    , Tw.border_color Theme.red_500
                    , Tw.bg_color Theme.red_500
                    ]
                ]
                []
            , div
                [ css
                    [ Tw.w_3
                    , Tw.h_3
                    , Tw.border_2
                    , Tw.rounded_full
                    , Tw.border_color Theme.yellow_400
                    , Tw.bg_color Theme.yellow_400
                    ]
                ]
                []
            , div
                [ css
                    [ Tw.w_3
                    , Tw.h_3
                    , Tw.border_2
                    , Tw.rounded_full
                    , Tw.border_color Theme.green_400
                    , Tw.bg_color Theme.green_400
                    ]
                ]
                []
            ]
        ]


elmCodeBlock : String -> Html msg
elmCodeBlock elmCode =
    SyntaxHighlight.elm elmCode
        |> Result.map (SyntaxHighlight.toBlockHtml (Just 1))
        |> Result.map Html.fromUnstyled
        |> Result.withDefault
            (Html.pre [] [ Html.code [] [ Html.text elmCode ] ])


codeTabs : ( String, String ) -> Html msg
codeTabs fileName =
    ul [ css [ Tw.flex, Tw.text_sm, Tw.text_color Theme.blue_200 ], Attr.style "transform" "translateY(0%) translateZ(0px);" ]
        [ codeTab 0 True fileName ]


codeTab : Int -> Bool -> ( String, String ) -> Html msg
codeTab index isCurrent ( fileName, fileContents ) =
    li
        [ css [ Tw.flex_none ]
        ]
        [ button
            [ Attr.type_ "button"
            , css
                [ Tw.border
                , Tw.border_color Theme.transparent
                , Tw.py_2
                , Tw.px_4
                , Tw.font_medium
                , Tw.text_color Theme.blue_200
                , if isCurrent then
                    Tw.bg_color Theme.blue_800

                  else
                    Tw.bg_color Theme.transparent
                , Css.focus [ Tw.outline_none ]
                , Css.hover [ Tw.text_color Theme.blue_100 ]
                ]
            ]
            [ text fileName ]
        ]
