module Route.Signup exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Head
import Head.Seo as Seo
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action _ =
    Request.expectFormPost
        (\{ field } ->
            Request.map2 Tuple.pair
                (field "first")
                (field "email")
                |> Request.map
                    (\( first, email ) ->
                        Success
                            { email = email
                            , first = first
                            }
                            |> Response.render
                            |> DataSource.succeed
                    )
        )


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias Data =
    {}


type ActionData
    = Success { email : String, first : String }
    | ValidationErrors
        { errors : List String
        , fields : List ( String, String )
        }


actionData : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
actionData routeParams =
    Debug.todo ""


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.succeed (DataSource.succeed (Response.render Data))


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    []


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View Msg
view maybeUrl sharedModel model static =
    View.placeholder "Signup"
