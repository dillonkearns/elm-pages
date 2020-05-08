module Pages.Internal.HotReloadLoadingIndicator exposing (..)

import Html exposing (Html, div)
import Html.Attributes exposing (..)


view : Bool -> Html msg
view hmrStatus =
    div
        [ id "__elm-pages-loading"
        , class "lds-default"
        , style "position" "fixed"
        , style "bottom" "10px"
        , style "right" "10px"
        , style "width" "80px"
        , style "height" "80px"
        , style "background-color" "white"
        , style "box-shadow" "0 8px 15px 0 rgba(0, 0, 0, 0.25), 0 2px 10px 0 rgba(0, 0, 0, 0.12)"
        , style "display"
            (case hmrStatus of
                True ->
                    "block"

                False ->
                    "none"
            )
        ]
        [ div
            [ style "animation-delay" "0s"
            , style "top" "37px"
            , style "left" "66px"
            ]
            []
        , div
            [ style "animation-delay" "-0.1s"
            , style "top" "22px"
            , style "left" "62px"
            ]
            []
        , div
            [ style "animation-delay" "-0.2s"
            , style "top" "11px"
            , style "left" "52px"
            ]
            []
        , div
            [ style "animation-delay" "-0.3s"
            , style "top" "7px"
            , style "left" "37px"
            ]
            []
        , div
            [ style "animation-delay" "-0.4s"
            , style "top" "11px"
            , style "left" "22px"
            ]
            []
        , div
            [ style "animation-delay" "-0.5s"
            , style "top" "22px"
            , style "left" "11px"
            ]
            []
        , div
            [ style "animation-delay" "-0.6s"
            , style "top" "37px"
            , style "left" "7px"
            ]
            []
        , div
            [ style "animation-delay" "-0.7s"
            , style "top" "52px"
            , style "left" "11px"
            ]
            []
        , div
            [ style "animation-delay" "-0.8s"
            , style "top" "62px"
            , style "left" "22px"
            ]
            []
        , div
            [ style "animation-delay" "-0.9s"
            , style "top" "66px"
            , style "left" "37px"
            ]
            []
        , div
            [ style "animation-delay" "-1s"
            , style "top" "62px"
            , style "left" "52px"
            ]
            []
        , div
            [ style "animation-delay" "-1.1s"
            , style "top" "52px"
            , style "left" "62px"
            ]
            []
        ]
