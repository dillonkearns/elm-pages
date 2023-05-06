module Stub exposing (..)

import Json.Decode as Decode
import Set exposing (Set)


type alias Id =
    Int


type alias Model =
    { nextId : Id
    , sentIds : Set Id
    }



--task : Task error value
--task =
--    Pending
--        (\id -> id)
--        (\value model -> ( model, Done (Ok value) ))


type Task error value
    = Pending (Id -> Id) (Decode.Value -> Model -> ( Model, Task error value ))
    | Done (Result error value)


map2 : (value1 -> value2 -> combined) -> Task error value1 -> Task error value2 -> Task error combined
map2 mapFn task1 task2 =
    case ( task1, task2 ) of
        ( Done resolved1, Done resolved2 ) ->
            Debug.todo ""

        ( Pending toId1 resolved1, Pending toId2 resolved2 ) ->
            Pending
                (\id ->
                    max (toId1 id) (toId2 id)
                        |> nextId
                )
                (\value id ->
                    Debug.todo ""
                )

        _ ->
            Debug.todo ""


nextId id =
    id + 1



--(Task toId1 resolve1)
--(Task toId2 resolve2)
