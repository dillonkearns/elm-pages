module Route.Users exposing (ActionData, Data, route, RouteParams, Msg, Model)

{-|

@docs ActionData, Data, route, RouteParams, Msg, Model

-}

import BackendTask
import BackendTask.Custom
import Effect
import ErrorPage
import FatalError
import Head
import Html
import Json.Decode as Decode
import Json.Encode as Encode
import Pages.PageUrl
import PagesMsg exposing (PagesMsg)
import Path
import Platform.Sub
import RouteBuilder
import Server.Request
import Server.Response
import Shared
import View


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : RouteBuilder.StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.buildWithLocalState
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
        (RouteBuilder.serverRender { data = data, action = action, head = head })


init :
    Shared.Model
    -> RouteBuilder.App Data ActionData RouteParams
    -> ( Model, Effect.Effect Msg )
init shared app =
    ( {}, Effect.none )


update :
    Shared.Model
    -> RouteBuilder.App Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect.Effect msg )
update shared app msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions :
    RouteParams
    -> Path.Path
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions routeParams path shared model =
    Sub.none


type alias Data =
    { users : List String
    }


type alias ActionData =
    {}


data :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response Data ErrorPage.ErrorPage))
data routeParams =
    Server.Request.succeed
        (BackendTask.Custom.run "users"
            Encode.null
            (Decode.list (Decode.field "name" Decode.string))
            |> BackendTask.allowFatal
            |> BackendTask.map
                (\users ->
                    Server.Response.render
                        { users = users
                        }
                )
        )


head : RouteBuilder.App Data ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    Shared.Model
    -> Model
    -> RouteBuilder.App Data ActionData RouteParams
    -> View.View (PagesMsg Msg)
view shared model app =
    { title = "Users"
    , body =
        [ Html.h2 [] [ Html.text "Users" ]
        , Html.text (app.data.users |> String.join ", ")
        ]
    }


action :
    RouteParams
    -> Server.Request.Parser (BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage))
action routeParams =
    Server.Request.succeed (BackendTask.succeed (Server.Response.render {}))
