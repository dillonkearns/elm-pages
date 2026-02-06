module View.Header exposing (..)

import Html exposing (..)
import Html.Attributes as Attr
import Html.Events
import Svg exposing (path, svg)
import Svg.Attributes as SvgAttr
import UrlPath exposing (UrlPath)


view : msg -> Int -> UrlPath -> Html msg
view toggleMobileMenuMsg stars currentPath =
    nav
        [ Attr.class "flex items-center bg-white z-20 sticky top-0 left-0 right-0 h-16 border-b border-gray-200 px-6"
        ]
        [ div
            [ Attr.class "w-full flex items-center"
            ]
            [ a
                [ Attr.class "no-underline text-current flex items-center hover:opacity-75"
                , Attr.href "/"
                ]
                [ span
                    [ Attr.class "mr-0 -ml-2 font-extrabold inline md:inline"
                    ]
                    [ text "elm-pages" ]
                ]
            ]
        , headerLink currentPath "showcase" "Showcase"
        , headerLink currentPath "blog" "Blog"
        , span
            [ Attr.class "hidden md:inline"
            ]
            [ headerLink currentPath "docs" "Docs" ]
        , button
            [ Attr.type_ "button"
            , Html.Events.onClick toggleMobileMenuMsg
            , Attr.class "flex items-center px-1 border border-gray-300 shadow-sm text-sm rounded-md text-gray-700 bg-white md:hidden focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 hover:bg-gray-50"
            ]
            [ linkInner currentPath "docs" "Docs"
            , svg
                [ SvgAttr.class "h-5 w-5"
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
            [ Attr.class "-mr-2"
            ]
            []
        ]


headerLink : UrlPath -> String -> String -> Html msg
headerLink currentPagePath linkTo name =
    a
        [ Attr.href ("/" ++ linkTo)
        , Attr.attribute "elm-pages:prefetch" "true"
        ]
        [ linkInner currentPagePath linkTo name ]


linkInner : UrlPath -> String -> String -> Html msg
linkInner currentPagePath linkTo name =
    let
        isCurrentPath : Bool
        isCurrentPath =
            List.head currentPagePath == Just linkTo
    in
    span
        [ Attr.class
            ("text-sm p-2 "
                ++ (if isCurrentPath then
                        "text-blue-600 hover:text-blue-700"

                    else
                        "text-gray-600 hover:text-gray-900"
                   )
            )
        ]
        [ text name ]
