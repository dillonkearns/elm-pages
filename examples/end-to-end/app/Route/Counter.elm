module Route.Counter exposing (ActionData, Data, Model, Msg, StaticData, route)

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
import RouteBuilder exposing (App, StatefulRoute, StatelessRoute)
import Shared
import UrlPath exposing (UrlPath)
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


type alias StaticData =
    ()


route : StatefulRoute RouteParams Data () ActionData Model Msg
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
    App Data () ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init app sharedModel =
    ( { count = Nothing }, Effect.GetStargazers GotStargazers )


update :
    App Data () ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )

        GotStargazers (Ok count) ->
            ( { count = Just count }, Effect.none )

        GotStargazers (Err error) ->
            ( model, Effect.none )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


data : BackendTask FatalError Data
data =
    BackendTask.succeed Data


head :
    App Data () ActionData RouteParams
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
    App Data () ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app sharedModel model =
    { title = "Counter"
    , body =
        [ case model.count of
            Nothing ->
                Html.text "Loading..."

            Just count ->
                Html.text ("The count is: " ++ String.fromInt count)
        ]
    }
