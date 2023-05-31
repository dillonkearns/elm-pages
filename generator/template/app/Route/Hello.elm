module Route.Hello exposing (ActionData, Data, Model, Msg(..), RouteParams, action, data, route)

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Head
import Html
import Json.Decode as Decode
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App)
import Server.Request exposing (Request)
import Server.Response
import Shared
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route =
    RouteBuilder.serverRender { data = data, action = action, head = head }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , subscriptions = subscriptions
            , update = update
            , init = init
            }


init :
    App Data ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect Msg )
init app shared =
    ( {}, Effect.none )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions :
    RouteParams
    -> UrlPath
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions routeParams path shared model =
    Sub.none


type alias Data =
    { stars : Int
    }


type alias ActionData =
    {}


data :
    RouteParams
    -> Request
    -> BackendTask FatalError (Server.Response.Response Data ErrorPage)
data routeParams request =
    BackendTask.Http.getWithOptions
        { url = "https://api.github.com/repos/dillonkearns/elm-pages"
        , expect = BackendTask.Http.expectJson (Decode.field "stargazers_count" Decode.int)
        , headers = []
        , cacheStrategy = Just BackendTask.Http.IgnoreCache
        , retries = Nothing
        , timeoutInMs = Nothing
        , cachePath = Nothing
        }
        |> BackendTask.allowFatal
        |> BackendTask.map
            (\stars -> Server.Response.render { stars = stars })


head : App Data ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View (PagesMsg Msg)
view app shared model =
    { title = "Hello", body = [ Html.text (String.fromInt app.data.stars) ] }


action :
    RouteParams
    -> Request
    -> BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage)
action routeParams request =
    BackendTask.succeed (Server.Response.render {})
