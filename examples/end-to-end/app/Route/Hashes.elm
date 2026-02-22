module Route.Hashes exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Html.Styled exposing (a, div, h2, text)
import Html.Styled.Attributes as Attr
import PagesMsg exposing (PagesMsg)
import Route
import RouteBuilder exposing (App, StatelessRoute)
import Shared
import View exposing (View)


type alias Model =
    {}


type alias Msg =
    ()


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias StaticData =
    ()


type alias Data =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildNoState { view = view }


data : BackendTask FatalError Data
data =
    BackendTask.succeed {}


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []


link : List (Html.Styled.Attribute msg) -> List (Html.Styled.Html msg) -> Route.Route -> Html.Styled.Html msg
link attributes children route_ =
    Route.toLink (\anchorAttrs -> a (List.map Attr.fromUnstyled anchorAttrs ++ attributes) children) route_


myDiv : Html.Styled.Html msg
myDiv =
    div [] [ text "Hello" ]


heading : String -> Html.Styled.Html msg
heading id =
    h2
        [ Attr.name id
        , Attr.id id
        ]
        [ a
            [ Attr.href ("#" ++ id) ]
            [ text id ]
        ]


divider : Html.Styled.Html msg
divider =
    div [] (List.repeat 40 myDiv)


view : App Data ActionData RouteParams -> Shared.Model -> View (PagesMsg Msg)
view _ _ =
    { title = "Hash navigation page"
    , body =
        [ heading "a"
        , divider
        , heading "b"
        , divider
        , heading "c"
        , divider
        , heading "d"
        , divider
        , Route.Hashes |> link [] [ text "Top of the page" ]
        ]
    }
