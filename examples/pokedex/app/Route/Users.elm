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
import PagesMsg exposing (PagesMsg)
import Platform.Sub
import RouteBuilder
import Server.Request exposing (Request)
import Server.Response
import Shared
import UrlPath
import View
import View.Static


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : RouteBuilder.StatefulRoute RouteParams Data () ActionData Model Msg
route =
    RouteBuilder.buildWithLocalState
        { view = view
        , init = init
        , update = update
        , subscriptions = subscriptions
        }
        (RouteBuilder.serverRender { data = data, action = action, head = head })


init :
    RouteBuilder.App Data () ActionData RouteParams
    -> Shared.Model
    -> ( Model, Effect.Effect Msg )
init shared app =
    ( {}, Effect.none )


update :
    RouteBuilder.App Data () ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect.Effect msg )
update app shared msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions :
    RouteParams
    -> UrlPath.UrlPath
    -> Shared.Model
    -> Model
    -> Sub Msg
subscriptions routeParams path shared model =
    Sub.none


{-| Static content for the users list - rendered at build/request time,
eliminated from client bundle.
-}
type alias StaticContent =
    { users : List String
    }


type alias Data =
    { staticContent : View.Static.StaticOnlyData StaticContent
    }


type alias ActionData =
    {}


data :
    RouteParams
    -> Request
    -> BackendTask.BackendTask FatalError.FatalError (Server.Response.Response Data ErrorPage.ErrorPage)
data routeParams request =
    BackendTask.Custom.run "users"
        Encode.null
        (Decode.list (Decode.field "name" Decode.string))
        |> BackendTask.allowFatal
        |> BackendTask.map
            (\users ->
                Server.Response.render
                    { staticContent = View.Static.wrap { users = users }
                    }
            )


head : RouteBuilder.App Data () ActionData RouteParams -> List Head.Tag
head app =
    []


view :
    RouteBuilder.App Data () ActionData RouteParams
    -> Shared.Model
    -> Model
    -> View.View (PagesMsg Msg)
view app shared model =
    { title = "Users"
    , body =
        [ Html.h2 [] [ Html.text "Users" ]
        , View.staticView app.data.staticContent renderUsers
        ]
    }


{-| Render the users list as a static region.
This code is eliminated from the client bundle via DCE.
-}
renderUsers : StaticContent -> View.Static
renderUsers content =
    Html.div []
        [ Html.text (content.users |> String.join ", ")
        ]


action :
    RouteParams
    -> Request
    -> BackendTask.BackendTask FatalError.FatalError (Server.Response.Response ActionData ErrorPage.ErrorPage)
action routeParams request =
    BackendTask.succeed (Server.Response.render {})
