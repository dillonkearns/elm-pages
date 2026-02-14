module NextPrevious exposing (..)

import Html exposing (..)
import Html.Attributes as Attr
import Route
import Svg exposing (path, svg)
import Svg.Attributes as SvgAttr


type alias Item =
    { title : String, slug : String }


view : ( Maybe Item, Maybe Item ) -> Html msg
view ( maybeLeft, maybeRight ) =
    div
        [ Attr.class "pt-16"
        ]
        [ nav
            [ Attr.class "flex flex-row items-center justify-between"
            ]
            [ maybeLeft
                |> Maybe.map
                    (\left ->
                        div []
                            [ link (Route.Docs__Section__ { section = Just left.slug })
                                [ Attr.class "text-lg font-medium p-4 -m-4 !no-underline !text-gray-600 flex items-center mr-2 hover:!text-blue-700"
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
                                [ Attr.class "text-lg font-medium p-4 -m-4 !no-underline !text-gray-600 flex items-center mr-2 hover:!text-blue-700"
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
                (anchorAttrs ++ attrs)
                children
        )
        route


empty : Html msg
empty =
    div [] []


leftArrow : Html msg
leftArrow =
    svg
        [ SvgAttr.height "24"
        , SvgAttr.fill "none"
        , SvgAttr.viewBox "0 0 24 24"
        , SvgAttr.stroke "currentColor"
        , SvgAttr.class "transform inline shrink-0 rotate-180 mr-1"
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
        , SvgAttr.class "transform inline shrink-0 ml-1"
        ]
        [ path
            [ SvgAttr.strokeLinecap "round"
            , SvgAttr.strokeLinejoin "round"
            , SvgAttr.strokeWidth "2"
            , SvgAttr.d "M9 5l7 7-7 7"
            ]
            []
        ]
