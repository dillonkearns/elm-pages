module Route.Counter exposing (ActionData, Data, Model, Msg(..), route)

{-| A simple counter page that demonstrates client-side TEA with Effect.SendMsg.
Data is loaded from a BackendTask, but all interactions are client-side.
Used to test the SimulatedEffect.DispatchMsg pipeline.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import FatalError exposing (FatalError)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (..)
import Html.Styled.Events exposing (onClick)
import Json.Decode as Decode
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Server.Request as Request exposing (Request)
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = \_ -> []
        , data = data
        , action = \_ _ -> BackendTask.succeed (Response.render {})
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = \_ _ _ _ -> Sub.none
            , init = init
            }


type alias RouteParams =
    {}


type alias Data =
    { initialCount : Int
    , label : String
    }


type alias ActionData =
    {}


type alias Model =
    { count : Int
    , label : String
    , history : List Int
    , effectFired : Bool
    }


type Msg
    = Increment
    | Decrement
    | Reset
    | RecordHistory


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init app _ =
    ( { count = app.data.initialCount
      , label = app.data.label
      , history = []
      , effectFired = False
      }
    , Effect.none
    )


update : App Data ActionData RouteParams -> Shared.Model -> Msg -> Model -> ( Model, Effect Msg )
update _ _ msg model =
    case msg of
        Increment ->
            ( { model | count = model.count + 1 }
            , Effect.SendMsg RecordHistory
            )

        Decrement ->
            ( { model | count = model.count - 1 }
            , Effect.SendMsg RecordHistory
            )

        Reset ->
            ( { model | count = 0, history = [] }
            , Effect.none
            )

        RecordHistory ->
            ( { model | history = model.count :: model.history, effectFired = True }
            , Effect.none
            )


data : RouteParams -> Request -> BackendTask FatalError (Response Data ErrorPage)
data _ _ =
    BackendTask.Http.getJson
        "https://api.example.com/counter"
        (Decode.map2 Data
            (Decode.field "initialCount" Decode.int)
            (Decode.field "label" Decode.string)
        )
        |> BackendTask.allowFatal
        |> BackendTask.map Response.render


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view _ _ model =
    { title = model.label ++ " Counter"
    , body =
        [ div []
            [ h1 [] [ text (model.label ++ " Counter") ]
            , p [ class "count" ] [ text ("Count: " ++ String.fromInt model.count) ]
            , button [ onClick (PagesMsg.fromMsg Decrement) ] [ text "-" ]
            , button [ onClick (PagesMsg.fromMsg Increment) ] [ text "+" ]
            , button [ onClick (PagesMsg.fromMsg Reset) ] [ text "Reset" ]
            , div [ class "history" ]
                [ text
                    ("History: "
                        ++ (model.history
                                |> List.reverse
                                |> List.map String.fromInt
                                |> String.join ", "
                           )
                    )
                ]
            , if model.effectFired then
                p [ class "effect-status" ] [ text "Effect fired!" ]
              else
                p [ class "effect-status" ] [ text "No effect yet" ]
            ]
        ]
    }
