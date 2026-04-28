module Effect exposing (Effect(..), none, batch, fromCmd, sendMsg, map, perform, testPerform)

{-| Minimal Effect module for the TEA-focused TodoMVC.

Most of the original todos example's effects (FetchRouteData, Submit,
SubmitFetcher) are replaced by `SendMsg` -- the client-side TEA pattern
where update returns a message to be dispatched, rather than a server
round-trip.

@docs Effect, none, batch, fromCmd, sendMsg, map, perform, testPerform

-}

import Browser.Navigation
import Http
import Pages.Fetcher
import Task
import Test.PagesProgram.SimulatedEffect as SimulatedEffect exposing (SimulatedEffect)
import Url exposing (Url)


{-| -}
type Effect msg
    = None
    | Cmd (Cmd msg)
    | Batch (List (Effect msg))
    | SendMsg msg


{-| -}
none : Effect msg
none =
    None


{-| -}
batch : List (Effect msg) -> Effect msg
batch =
    Batch


{-| -}
fromCmd : Cmd msg -> Effect msg
fromCmd =
    Cmd


{-| Dispatch a message through the update cycle. -}
sendMsg : msg -> Effect msg
sendMsg =
    SendMsg


{-| -}
map : (a -> b) -> Effect a -> Effect b
map fn effect =
    case effect of
        None ->
            None

        Cmd cmd ->
            Cmd (Cmd.map fn cmd)

        Batch list ->
            Batch (List.map (map fn) list)

        SendMsg msg ->
            SendMsg (fn msg)


{-| -}
perform :
    { fetchRouteData :
        { data : Maybe a
        , toMsg : Result Http.Error Url -> pageMsg
        }
        -> Cmd msg
    , submit :
        { values : b
        , toMsg : Result Http.Error Url -> pageMsg
        }
        -> Cmd msg
    , runFetcher :
        Pages.Fetcher.Fetcher pageMsg
        -> Cmd msg
    , fromPageMsg : pageMsg -> msg
    , key : Browser.Navigation.Key
    , setField : { formId : String, name : String, value : String } -> Cmd msg
    }
    -> Effect pageMsg
    -> Cmd msg
perform ({ fromPageMsg } as helpers) effect =
    case effect of
        None ->
            Cmd.none

        Cmd cmd ->
            Cmd.map fromPageMsg cmd

        Batch list ->
            Cmd.batch (List.map (perform helpers) list)

        SendMsg msg ->
            Task.succeed (fromPageMsg msg) |> Task.perform identity


{-| Decompose an Effect into a SimulatedEffect for the test framework.
-}
testPerform : Effect msg -> SimulatedEffect msg
testPerform effect =
    case effect of
        None ->
            SimulatedEffect.none

        Cmd _ ->
            SimulatedEffect.none

        Batch list ->
            SimulatedEffect.batch (List.map testPerform list)

        SendMsg msg ->
            SimulatedEffect.dispatchMsg msg
