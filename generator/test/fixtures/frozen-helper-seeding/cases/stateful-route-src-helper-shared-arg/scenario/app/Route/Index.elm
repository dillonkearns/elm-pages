module Route.Index exposing (ActionData, Data, Model, Msg, StaticData, route)

import BackendTask exposing (BackendTask)
import ContentPage
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Html.Styled as Html
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { counter : Int
    }


type Msg
    = Increment


type alias RouteParams =
    {}


type alias ActionData =
    {}


type alias StaticData =
    ()


type alias Data =
    { title : String
    }


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , init = init
            , update = update
            , subscriptions = subscriptions
            }


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init _ _ =
    ( { counter = 0 }, Effect.none )


update : App Data ActionData RouteParams -> Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update _ _ msg model =
    case msg of
        Increment ->
            ( { model | counter = model.counter + 1 }, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions _ _ _ _ =
    Sub.none


data : BackendTask FatalError Data
data =
    BackendTask.succeed
        { title = "Hello"
        }


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head _ =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared _ =
    { title = "Stateful Route with Src Helper"
    , body =
        [ Html.h1 [] [ Html.text "Stateful route test" ]
        , ContentPage.view app.data shared
        ]
    }
