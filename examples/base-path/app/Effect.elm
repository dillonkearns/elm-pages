module Effect exposing (Effect(..), batch, fromCmd, map, none, perform)

import Browser.Navigation


type Effect msg
    = None
    | Cmd (Cmd msg)
    | Batch (List (Effect msg))


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


perform : (pageMsg -> msg) -> Browser.Navigation.Key -> Effect pageMsg -> Cmd msg
perform fromPageMsg key effect =
    case effect of
        None ->
            Cmd.none

        Cmd cmd ->
            Cmd.map fromPageMsg cmd

        Batch list ->
            Cmd.batch (List.map (perform fromPageMsg key) list)
