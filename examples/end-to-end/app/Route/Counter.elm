module Route.Counter exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Head.Seo as Seo
import Html.Styled as Html
import Http
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import PagesMsg exposing (PagesMsg)
import Path exposing (Path)
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Shared
import View exposing (View)


type alias Model =
    { count : Maybe Int
    }


type Msg
    = NoOp
    | GotStargazers (Result Http.Error Int)


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
    Shared.Model
    -> App Data ActionData RouteParams
    -> ( Model, Effect Msg )
init sharedModel app =
    ( { count = Nothing }, Effect.GetStargazers GotStargazers )


update :
    Shared.Model
    -> App Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update shared app msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )

        GotStargazers (Ok count) ->
            ( { count = Just count }, Effect.none )

        GotStargazers (Err error) ->
            ( model, Effect.none )


subscriptions : RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
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
        , description = "TODO"
        , locale = Nothing
        , title = "Counter"
        }
        |> Seo.website


view :
    Shared.Model
    -> Model
    -> App Data ActionData RouteParams
    -> View (PagesMsg Msg)
view sharedModel model app =
    { title = "Counter"
    , body =
        [ case model.count of
            Nothing ->
                Html.text "Loading..."

            Just count ->
                Html.text ("The count is: " ++ String.fromInt count)
        ]
    }
