module TestState exposing (TestState, advanceTime, drain, queueEffect, update, urlChangeHelper, urlRequestHelper, withSimulation)

import Dict
import PairingHeap
import ProgramTest.EffectSimulation as EffectSimulation exposing (EffectSimulation)
import ProgramTest.Failure exposing (Failure(..))
import ProgramTest.Program exposing (Program)
import SimulatedEffect exposing (SimulatedEffect)
import String.Extra
import Url exposing (Url)
import Url.Extra


{-| TODO: what's a better name?
-}
type alias TestState model msg effect =
    { currentModel : model
    , lastEffect : effect
    , navigation :
        Maybe
            { currentLocation : Url
            , browserHistory : List Url
            }
    , effectSimulation : Maybe (EffectSimulation msg effect)
    }


update : msg -> Program model msg effect sub -> TestState model msg effect -> Result Failure (TestState model msg effect)
update msg program state =
    let
        ( newModel, newEffect ) =
            program.update msg state.currentModel
    in
    { state
        | currentModel = newModel
        , lastEffect = newEffect
    }
        |> queueEffect program newEffect
        |> Result.andThen (drain program)


queueEffect : Program model msg effect sub -> effect -> TestState model msg effect -> Result Failure (TestState model msg effect)
queueEffect program effect state =
    case state.effectSimulation of
        Nothing ->
            Ok state

        Just simulation ->
            queueSimulatedEffect program (simulation.deconstructEffect effect) state


queueSimulatedEffect : Program model msg effect sub -> SimulatedEffect msg -> TestState model msg effect -> Result Failure (TestState model msg effect)
queueSimulatedEffect program effect state =
    case state.effectSimulation of
        Nothing ->
            Ok state

        Just simulation ->
            case effect of
                SimulatedEffect.None ->
                    Ok state

                SimulatedEffect.Batch effects ->
                    List.foldl (\ef -> Result.andThen (queueSimulatedEffect program ef)) (Ok state) effects

                SimulatedEffect.Task t ->
                    Ok
                        { state
                            | effectSimulation =
                                Just (EffectSimulation.queueTask t simulation)
                        }

                SimulatedEffect.PortEffect portName value ->
                    Ok
                        { state
                            | effectSimulation =
                                Just
                                    { simulation
                                        | outgoingPortValues =
                                            Dict.update portName
                                                (Maybe.withDefault [] >> (::) value >> Just)
                                                simulation.outgoingPortValues
                                    }
                        }

                SimulatedEffect.PushUrl url ->
                    urlChangeHelper ("simulating effect: SimulatedEffect.Navigation.pushUrl " ++ String.Extra.escape url) 0 url program state

                SimulatedEffect.ReplaceUrl url ->
                    urlChangeHelper ("simulating effect: SimulatedEffect.Navigation.replaceUrl " ++ String.Extra.escape url) 1 url program state

                SimulatedEffect.Back n ->
                    case state.navigation of
                        Nothing ->
                            Ok state

                        Just { currentLocation, browserHistory } ->
                            if n <= 0 then
                                Ok state

                            else
                                case List.head (List.drop (n - 1) browserHistory) of
                                    Nothing ->
                                        -- n is bigger than the history;
                                        -- in this case, browsers ignore the request
                                        Ok state

                                    Just first ->
                                        urlChangeHelper ("simulating effect: SimulatedEffect.Navigation.Back " ++ String.fromInt n) 2 (Url.toString first) program state

                SimulatedEffect.Load url ->
                    Err (simulateLoadUrlHelper ("simulating effect: SimulatedEffect.Navigation.load " ++ url) url state)

                SimulatedEffect.Reload skipCache ->
                    let
                        functionName =
                            if skipCache then
                                "reloadAndSkipCache"

                            else
                                "reload"
                    in
                    case state.navigation of
                        Nothing ->
                            Err (ProgramDoesNotSupportNavigation functionName)

                        Just { currentLocation } ->
                            Err (ChangedPage ("simulating effect: SimulatedEffect.Navigation." ++ functionName) currentLocation)


simulateLoadUrlHelper : String -> String -> TestState model msg effect -> Failure
simulateLoadUrlHelper functionDescription href state =
    case Maybe.map .currentLocation state.navigation of
        Just location ->
            ChangedPage functionDescription (Url.Extra.resolve location href)

        Nothing ->
            case Url.fromString href of
                Nothing ->
                    NoBaseUrl functionDescription href

                Just location ->
                    ChangedPage functionDescription location


urlRequestHelper : String -> String -> Program model msg effect sub -> TestState model msg effect -> Result Failure (TestState model msg effect)
urlRequestHelper functionDescription href program state =
    case Maybe.map .currentLocation state.navigation of
        Just location ->
            case program.onUrlRequest of
                Just onUrlRequest ->
                    update (onUrlRequest (Url.Extra.toUrlRequest location href)) program state

                Nothing ->
                    Err (ChangedPage functionDescription (Url.Extra.resolve location href))

        Nothing ->
            case Url.fromString href of
                Nothing ->
                    Err (NoBaseUrl functionDescription href)

                Just location ->
                    Err (ChangedPage functionDescription location)


urlChangeHelper : String -> Int -> String -> Program model msg effect sub -> TestState model msg effect -> Result Failure (TestState model msg effect)
urlChangeHelper functionName removeFromBackStack url program state =
    case state.navigation of
        Nothing ->
            Err (ProgramDoesNotSupportNavigation functionName)

        Just { currentLocation, browserHistory } ->
            let
                newLocation =
                    Url.Extra.resolve currentLocation url

                processRouteChange =
                    case program.onUrlChange of
                        Nothing ->
                            Ok

                        Just onUrlChange ->
                            -- TODO: should this be set before or after?
                            update (onUrlChange newLocation) program
            in
            { state
                | navigation =
                    Just
                        { currentLocation = newLocation
                        , browserHistory =
                            (currentLocation :: browserHistory)
                                |> List.drop removeFromBackStack
                        }
            }
                |> processRouteChange


drain : Program model msg effect sub -> TestState model msg effect -> Result Failure (TestState model msg effect)
drain program =
    let
        advanceTimeIfSimulating t state =
            case state.effectSimulation of
                Nothing ->
                    Ok state

                Just _ ->
                    advanceTime "<UNKNOWN LOCATION: if you see this, please report it at https://github.com/avh4/elm-program-test/issues/>" t program state
    in
    advanceTimeIfSimulating 0
        >> Result.andThen (drainWorkQueue program)


drainWorkQueue : Program model msg effect sub -> TestState model msg effect -> Result Failure (TestState model msg effect)
drainWorkQueue program state =
    case state.effectSimulation of
        Nothing ->
            Ok state

        Just simulation ->
            case EffectSimulation.stepWorkQueue simulation of
                Nothing ->
                    -- work queue is empty
                    Ok state

                Just ( newSimulation, msg ) ->
                    let
                        updateMaybe tc =
                            case msg of
                                Nothing ->
                                    Ok tc

                                Just m ->
                                    update m program tc
                    in
                    { state | effectSimulation = Just newSimulation }
                        |> updateMaybe
                        |> Result.andThen (drain program)


advanceTime : String -> Int -> Program model msg effect sub -> TestState model msg effect -> Result Failure (TestState model msg effect)
advanceTime functionName delta program state =
    case state.effectSimulation of
        Nothing ->
            Err (EffectSimulationNotConfigured functionName)

        Just simulation ->
            advanceTo program functionName (simulation.state.nowMs + delta) state


advanceTo : Program model msg effect sub -> String -> Int -> TestState model msg effect -> Result Failure (TestState model msg effect)
advanceTo program functionName end state =
    case state.effectSimulation of
        Nothing ->
            Err (EffectSimulationNotConfigured functionName)

        Just simulation ->
            let
                ss =
                    simulation.state
            in
            case PairingHeap.findMin simulation.state.futureTasks of
                Nothing ->
                    -- No future tasks to check
                    Ok
                        { state
                            | effectSimulation =
                                Just
                                    { simulation
                                        | state = { ss | nowMs = end }
                                    }
                        }

                Just ( t, task ) ->
                    if t <= end then
                        Ok
                            { state
                                | effectSimulation =
                                    Just
                                        { simulation
                                            | state =
                                                { ss
                                                    | nowMs = t
                                                    , futureTasks = PairingHeap.deleteMin simulation.state.futureTasks
                                                }
                                        }
                            }
                            |> Result.map (withSimulation (EffectSimulation.queueTask (task ())))
                            |> Result.andThen (drain program)
                            |> Result.andThen (advanceTo program functionName end)

                    else
                        -- next task is further in the future than we are advancing
                        Ok
                            { state
                                | effectSimulation =
                                    Just
                                        { simulation
                                            | state = { ss | nowMs = end }
                                        }
                            }


withSimulation : (EffectSimulation msg effect -> EffectSimulation msg effect) -> TestState model msg effect -> TestState model msg effect
withSimulation f state =
    { state | effectSimulation = Maybe.map f state.effectSimulation }
