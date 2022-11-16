module SimulatedEffect.Task exposing
    ( perform, attempt
    , andThen, succeed, fail, sequence
    , map, map2, map3, map4, map5
    , mapError, onError
    )

{-| This module parallels [elm/core's `Task` module](https://package.elm-lang.org/packages/elm/core/1.0.2/Task).
_Pull requests are welcome to add any functions that are missing._

The functions here produce `SimulatedTasks`s instead of `Tasks`s
and `SimulatedEffect`s instead of `Cmd`s, which are meant to be used
to help you implement the function to provide when using [`ProgramTest.withSimulatedEffects`](ProgramTest#withSimulatedEffects).


# Tasks

@docs perform, attempt


# Chains

@docs andThen, succeed, fail, sequence


# Maps

@docs map, map2, map3, map4, map5


# Errors

@docs mapError, onError

-}

import ProgramTest exposing (SimulatedEffect, SimulatedTask)
import SimulatedEffect


{-| -}
perform : (a -> msg) -> SimulatedTask Never a -> SimulatedEffect msg
perform f task =
    task
        |> map f
        |> mapError never
        |> SimulatedEffect.Task


{-| This is very similar to [`perform`](#perform) except it can handle failures!
-}
attempt : (Result x a -> msg) -> SimulatedTask x a -> SimulatedEffect msg
attempt f task =
    task
        |> map (Ok >> f)
        |> mapError (Err >> f)
        |> SimulatedEffect.Task


{-| Chain together a task and a callback.
-}
andThen : (a -> SimulatedTask x b) -> SimulatedTask x a -> SimulatedTask x b
andThen f task =
    case task of
        SimulatedEffect.Succeed a ->
            f a

        SimulatedEffect.Fail x ->
            SimulatedEffect.Fail x

        SimulatedEffect.HttpTask request ->
            SimulatedEffect.HttpTask
                { method = request.method
                , url = request.url
                , body = request.body
                , headers = request.headers
                , onRequestComplete = request.onRequestComplete >> andThen f
                }

        SimulatedEffect.SleepTask delay onResult ->
            SimulatedEffect.SleepTask delay (onResult >> andThen f)

        SimulatedEffect.NowTask onResult ->
            SimulatedEffect.NowTask (onResult >> andThen f)


{-| A task that succeeds immediately when run.
-}
succeed : a -> SimulatedTask x a
succeed =
    SimulatedEffect.Succeed


{-| A task that fails immediately when run.
-}
fail : x -> SimulatedTask x a
fail =
    SimulatedEffect.Fail


{-| Start with a list of tasks, and turn them into a single task that returns a
list.
-}
sequence : List (SimulatedTask x a) -> SimulatedTask x (List a)
sequence tasks =
    List.foldr (map2 (::)) (succeed []) tasks


{-| Transform a task.
-}
map : (a -> b) -> SimulatedTask x a -> SimulatedTask x b
map f =
    andThen (f >> SimulatedEffect.Succeed)


{-| Put the results of two tasks together.
-}
map2 : (a -> b -> result) -> SimulatedTask x a -> SimulatedTask x b -> SimulatedTask x result
map2 func taskA taskB =
    taskA
        |> andThen
            (\a ->
                taskB
                    |> andThen (\b -> succeed (func a b))
            )


{-| Put the results of three tasks together.
-}
map3 : (a -> b -> c -> result) -> SimulatedTask x a -> SimulatedTask x b -> SimulatedTask x c -> SimulatedTask x result
map3 func taskA taskB taskC =
    taskA
        |> andThen
            (\a ->
                taskB
                    |> andThen
                        (\b ->
                            taskC
                                |> andThen (\c -> succeed (func a b c))
                        )
            )


{-| Put the results of four tasks together.
-}
map4 :
    (a -> b -> c -> d -> result)
    -> SimulatedTask x a
    -> SimulatedTask x b
    -> SimulatedTask x c
    -> SimulatedTask x d
    -> SimulatedTask x result
map4 func taskA taskB taskC taskD =
    taskA
        |> andThen
            (\a ->
                taskB
                    |> andThen
                        (\b ->
                            taskC
                                |> andThen
                                    (\c ->
                                        taskD
                                            |> andThen (\d -> succeed (func a b c d))
                                    )
                        )
            )


{-| Put the results of five tasks together.
-}
map5 :
    (a -> b -> c -> d -> e -> result)
    -> SimulatedTask x a
    -> SimulatedTask x b
    -> SimulatedTask x c
    -> SimulatedTask x d
    -> SimulatedTask x e
    -> SimulatedTask x result
map5 func taskA taskB taskC taskD taskE =
    taskA
        |> andThen
            (\a ->
                taskB
                    |> andThen
                        (\b ->
                            taskC
                                |> andThen
                                    (\c ->
                                        taskD
                                            |> andThen
                                                (\d ->
                                                    taskE
                                                        |> andThen (\e -> succeed (func a b c d e))
                                                )
                                    )
                        )
            )


{-| Transform the error value.
-}
mapError : (x -> y) -> SimulatedTask x a -> SimulatedTask y a
mapError f task =
    case task of
        SimulatedEffect.Succeed a ->
            SimulatedEffect.Succeed a

        SimulatedEffect.Fail x ->
            SimulatedEffect.Fail (f x)

        SimulatedEffect.HttpTask request ->
            SimulatedEffect.HttpTask
                { method = request.method
                , url = request.url
                , body = request.body
                , headers = request.headers
                , onRequestComplete = request.onRequestComplete >> mapError f
                }

        SimulatedEffect.SleepTask delay onResult ->
            SimulatedEffect.SleepTask delay (onResult >> mapError f)

        SimulatedEffect.NowTask onResult ->
            SimulatedEffect.NowTask (onResult >> mapError f)


{-| Recover from a failure in a task.
-}
onError : (x -> SimulatedTask y a) -> SimulatedTask x a -> SimulatedTask y a
onError f task =
    case task of
        SimulatedEffect.Succeed a ->
            SimulatedEffect.Succeed a

        SimulatedEffect.Fail x ->
            f x

        SimulatedEffect.HttpTask request ->
            SimulatedEffect.HttpTask
                { method = request.method
                , url = request.url
                , body = request.body
                , headers = request.headers
                , onRequestComplete = request.onRequestComplete >> onError f
                }

        SimulatedEffect.SleepTask delay onResult ->
            SimulatedEffect.SleepTask delay (onResult >> onError f)

        SimulatedEffect.NowTask onResult ->
            SimulatedEffect.NowTask (onResult >> onError f)
