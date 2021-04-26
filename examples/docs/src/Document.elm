module Document exposing (Document, View(..), map)

import Element exposing (Element)
import Html.Styled as Html exposing (Html)


type alias Document msg =
    { title : String
    , body : View msg
    }


map : (msg1 -> msg2) -> Document msg1 -> Document msg2
map fn doc =
    { title = doc.title
    , body = mapView fn doc.body
    }


type View msg
    = ElmUiView (List (Element msg))
    | ElmCssView (List (Html msg))


mapView : (msg1 -> msg2) -> View msg1 -> View msg2
mapView fn view =
    case view of
        ElmUiView elements ->
            List.map (Element.map fn) elements
                |> ElmUiView

        ElmCssView elements ->
            List.map (Html.map fn) elements
                |> ElmCssView


placeholder : String -> Document msg
placeholder moduleName =
    { title = "Placeholder"
    , body = ElmUiView [ Element.text moduleName ]
    }
