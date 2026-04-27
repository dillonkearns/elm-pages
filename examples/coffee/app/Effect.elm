module Effect exposing (Effect(..), batch, fromCmd, map, none, perform, testPerform)

import Browser.Navigation
import Http
import Json.Decode as Decode
import Pages.Fetcher
import Task
import Test.PagesProgram.SimulatedEffect as SimulatedEffect exposing (SimulatedEffect)
import Url exposing (Url)


type Effect msg
    = None
    | Cmd (Cmd msg)
    | Batch (List (Effect msg))
    | SendMsg msg
    | GetStargazers (Result Http.Error Int -> msg)
    | SetField { formId : String, name : String, value : String }
    | SubmitFetcher (Pages.Fetcher.Fetcher msg)


none : Effect msg
none =
    None


batch : List (Effect msg) -> Effect msg
batch =
    Batch


fromCmd : Cmd msg -> Effect msg
fromCmd =
    Cmd


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

        GetStargazers toMsg ->
            GetStargazers (toMsg >> fn)

        SetField info ->
            SetField info

        SubmitFetcher fetcher ->
            fetcher
                |> Pages.Fetcher.map fn
                |> SubmitFetcher


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
perform ({ fromPageMsg, key } as helpers) effect =
    case effect of
        None ->
            Cmd.none

        Cmd cmd ->
            Cmd.map fromPageMsg cmd

        SetField info ->
            helpers.setField info

        SendMsg msg ->
            Task.succeed (fromPageMsg msg) |> Task.perform identity

        Batch list ->
            Cmd.batch (List.map (perform helpers) list)

        GetStargazers toMsg ->
            Http.get
                { url =
                    "https://api.github.com/repos/dillonkearns/elm-pages"
                , expect = Http.expectJson (toMsg >> fromPageMsg) (Decode.field "stargazers_count" Decode.int)
                }

        SubmitFetcher record ->
            helpers.runFetcher record


testPerform : Effect msg -> SimulatedEffect msg
testPerform effect =
    case effect of
        None ->
            SimulatedEffect.none

        Cmd _ ->
            SimulatedEffect.none

        SendMsg msg ->
            SimulatedEffect.dispatchMsg msg

        Batch list ->
            SimulatedEffect.batch (List.map testPerform list)

        GetStargazers toMsg ->
            SimulatedEffect.dispatchMsg (toMsg (Ok 0))

        SetField info ->
            SimulatedEffect.setField info

        SubmitFetcher fetcher ->
            SimulatedEffect.submitFetcher fetcher
