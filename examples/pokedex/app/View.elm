module View exposing (View, map, placeholder, Static, staticView, embedStatic)

import Html exposing (Html)
import View.Static


type alias View msg =
    { title : String
    , body : List (Html msg)
    }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn doc =
    { title = doc.title
    , body = List.map (Html.map fn) doc.body
    }


placeholder : String -> View msg
placeholder moduleName =
    { title = "Placeholder - " ++ moduleName
    , body = [ Html.text moduleName ]
    }


{-| Static content type - Html that cannot produce messages.
Used for content that is pre-rendered at build time and adopted by virtual-dom.
-}
type alias Static =
    Html Never


{-| Embed static content into a View body.
-}
embedStatic : Html Never -> Html msg
embedStatic content =
    Html.map never content


{-| Render static content using static-only data.

    view app =
        { body =
            [ View.staticView app.data.staticContent renderContent
            ]
        }

-}
staticView : View.Static.StaticOnlyData a -> (a -> Static) -> Html msg
staticView staticOnlyData renderFn =
    View.Static.view staticOnlyData renderFn
        |> Html.map never
