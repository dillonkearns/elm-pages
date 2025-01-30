module AriaLiveAnnouncer exposing (view)

import Html exposing (Html)
import Html.Attributes as Attr
import Html.Lazy


{-| This ensures that page changes are announced with screen readers.

Inspired by <https://www.gatsbyjs.com/blog/2020-02-10-accessible-client-side-routing-improvements/>.

-}
view : String -> Html msg
view title =
    Html.Lazy.lazy mainView title


mainView : String -> Html msg
mainView title =
    -- NOTE: If you make changes here, also update pre-render-html.js!
    Html.div
        [ Attr.id "elm-pages-announcer"
        , Attr.attribute "aria-live" "assertive"
        , Attr.attribute "aria-atomic" "true"

        --, Attr.attribute "ref" reference
        , Attr.style "position" "absolute"
        , Attr.style "top" "0"
        , Attr.style "width" "1px"
        , Attr.style "height" "1px"
        , Attr.style "padding" "0"
        , Attr.style "overflow" "hidden"
        , Attr.style "clip" "rect(0, 0, 0, 0)"
        , Attr.style "whiteSpace" "nowrap"
        , Attr.style "border" "0"
        ]
        [ Html.text <| "Navigated to " ++ title ]
