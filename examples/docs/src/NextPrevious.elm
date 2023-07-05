module NextPrevious exposing (..)

import Css
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css)
import Route
import Svg.Styled exposing (path, svg)
import Svg.Styled.Attributes as SvgAttr
import Tailwind.Theme as Theme
import Tailwind.Utilities as Tw


type alias Item =
    { title : String, slug : String }


view : ( Maybe Item, Maybe Item ) -> Html msg
view ( maybeLeft, maybeRight ) =
    div
        [ css
            [ Tw.pt_16
            ]
        ]
        [ nav
            [ css
                [ Tw.flex
                , Tw.flex_row
                , Tw.items_center
                , Tw.justify_between
                ]
            ]
            [ maybeLeft
                |> Maybe.map
                    (\left ->
                        div []
                            [ link (Route.Docs__Section__ { section = Just left.slug })
                                [ linkStyle
                                , Attr.title left.title
                                ]
                                [ leftArrow
                                , text left.title
                                ]
                            ]
                    )
                |> Maybe.withDefault empty
            , maybeRight
                |> Maybe.map
                    (\right ->
                        div []
                            [ link (Route.Docs__Section__ { section = Just right.slug })
                                [ linkStyle
                                , Attr.title right.title
                                ]
                                [ text right.title
                                , rightArrow
                                ]
                            ]
                    )
                |> Maybe.withDefault empty
            ]
        ]


link : Route.Route -> List (Attribute msg) -> List (Html msg) -> Html msg
link route attrs children =
    Route.toLink
        (\anchorAttrs ->
            a
                (List.map Attr.fromUnstyled anchorAttrs ++ attrs)
                children
        )
        route


empty : Html msg
empty =
    div [] []


linkStyle : Attribute msg
linkStyle =
    css
        [ Tw.text_lg
        , Tw.font_medium
        , Tw.p_4
        , Tw.neg_m_4
        , Tw.no_underline |> Css.important
        , Tw.text_color Theme.gray_600 |> Css.important
        , Tw.flex
        , Tw.items_center
        , Tw.mr_2
        , Css.hover
            [ Tw.text_color Theme.blue_700 |> Css.important
            ]
        ]


leftArrow : Html msg
leftArrow =
    svg
        [ SvgAttr.height "24"
        , SvgAttr.fill "none"
        , SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.stroke "currentColor"
        , SvgAttr.css
            [ Tw.transform
            , Tw.inline
            , Tw.flex_shrink_0
            , Css.rotate (Css.deg 180) |> Css.transform
            , Tw.mr_1
            ]
        ]
        [ path
            [ SvgAttr.strokeLinecap "round"
            , SvgAttr.strokeLinejoin "round"
            , SvgAttr.strokeWidth "2"
            , SvgAttr.d "M9 5l7 7-7 7"
            ]
            []
        ]


rightArrow : Html msg
rightArrow =
    svg
        [ SvgAttr.height "24"
        , SvgAttr.fill "none"
        , SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.stroke "currentColor"
        , SvgAttr.css
            [ Tw.transform
            , Tw.inline
            , Tw.flex_shrink_0
            , Tw.ml_1
            ]
        ]
        [ path
            [ SvgAttr.strokeLinecap "round"
            , SvgAttr.strokeLinejoin "round"
            , SvgAttr.strokeWidth "2"
            , SvgAttr.d "M9 5l7 7-7 7"
            ]
            []
        ]


downArrow : Html msg
downArrow =
    svg
        [ SvgAttr.fill "none"
        , SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.strokeWidth "1.5"
        , SvgAttr.stroke "currentColor"
        , SvgAttr.css
            [ Tw.w_6
            , Tw.h_6
            ]
        ]
        [ path
            [ SvgAttr.strokeLinecap "round"
            , SvgAttr.strokeLinejoin "round"
            , SvgAttr.d "M19.5 8.25l-7.5 7.5-7.5-7.5"
            ]
            []
        ]
