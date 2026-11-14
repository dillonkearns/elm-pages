module Route.LazyInKeyed exposing (ActionData, Data, Model, Msg, RouteParams, route)

{-| Lazy nodes inside keyed nodes, for checking the HTML that the server sends.

See cypress/dev-default/server-rendered-html.cy.js and
<https://github.com/dillonkearns/elm-pages/issues/622>.

-}

import BackendTask exposing (BackendTask)
import FatalError exposing (FatalError)
import Head
import Html.Styled as Html exposing (Html)
import Html.Styled.Keyed as HtmlKeyed
import Html.Styled.Lazy as HtmlLazy
import PagesMsg exposing (PagesMsg)
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


type alias Data =
    {}


route : StatelessRoute RouteParams Data ActionData
route =
    RouteBuilder.single
        { head = \_ -> []
        , data = BackendTask.succeed {}
        }
        |> RouteBuilder.buildNoState { view = view }


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> View (PagesMsg Msg)
view app shared =
    { title = "Lazy in keyed"
    , body =
        [ HtmlKeyed.ul []
            [ ( "direct", HtmlLazy.lazy item "Lazy node directly inside a keyed node" )
            , ( "nested"
              , Html.li []
                    [ HtmlKeyed.node "div"
                        []
                        [ ( "inner", HtmlLazy.lazy paragraph "Lazy node inside nested keyed nodes" ) ]
                    ]
              )
            ]
        ]
    }


item : String -> Html msg
item label =
    Html.li [] [ Html.text label ]


paragraph : String -> Html msg
paragraph label =
    Html.p [] [ Html.text label ]
