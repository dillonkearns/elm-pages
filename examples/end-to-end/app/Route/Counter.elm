module Route.Counter exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled as Html
import Html.Styled.Events as Events
import Pages.Url
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { count : Int
    }


type Msg
    = Increment
    | Decrement
    | Reset


type alias RouteParams =
    {}


type alias ActionData =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init app sharedModel =
    ( { count = 0 }, Effect.none )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
    case msg of
        Increment ->
            ( { model | count = model.count + 1 }, Effect.none )

        Decrement ->
            ( { model | count = model.count - 1 }, Effect.none )

        Reset ->
            ( { model | count = 0 }, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


data : BackendTask FatalError Data
data =
    BackendTask.succeed Data


head :
    App Data ActionData RouteParams
    -> List Head.Tag
head app =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "A simple counter"
        , locale = Nothing
        , title = "Counter"
        }
        |> Seo.website


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app sharedModel model =
    { title = "Counter"
    , body =
        [ Html.div []
            [ Html.h1 [] [ Html.text "Counter" ]
            , Html.p []
                [ Html.text ("Count: " ++ String.fromInt model.count)
                ]
            , Html.button
                [ Events.onClick (PagesMsg.fromMsg Decrement) ]
                [ Html.text "-" ]
            , Html.button
                [ Events.onClick (PagesMsg.fromMsg Increment) ]
                [ Html.text "+" ]
            , Html.button
                [ Events.onClick (PagesMsg.fromMsg Reset) ]
                [ Html.text "Reset" ]
            ]
        ]
    }
