module Tui.Internal exposing (run)

{-| Internal TUI loop implementation. Not exposed to users.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Tui exposing (Context, Screen)
import Tui.Effect as Effect exposing (Effect)
import Tui.Sub as Sub exposing (Sub)


{-| Run the TUI loop. Called by `Script.tui` after the `data` BackendTask
completes.
-}
run :
    { init : data -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Sub msg
    }
    -> data
    -> BackendTask FatalError ()
run config loadedData =
    tuiInit
        |> BackendTask.andThen
            (\context ->
                let
                    ( initialModel, initialEffect ) =
                        config.init loadedData
                in
                processEffectsThenRenderAndWait config context initialModel initialEffect
            )



-- INTERNAL REQUESTS


{-| Enter TUI mode: alternate screen, raw mode, hide cursor. Returns the
initial terminal dimensions.
-}
tuiInit : BackendTask FatalError Context
tuiInit =
    BackendTask.Internal.Request.request
        { name = "tui-init"
        , body = BackendTask.Http.emptyBody
        , expect =
            BackendTask.Http.expectJson
                (Decode.map2 (\w h -> { width = w, height = h })
                    (Decode.field "width" Decode.int)
                    (Decode.field "height" Decode.int)
                )
        }


{-| Render screen and wait for next event(s). Returns either a single event
or a batch of events that arrived in the same tick (like gocui's event drain).
-}
tuiRenderAndWait : Screen -> Sub msg -> BackendTask FatalError { events : List Decode.Value, width : Int, height : Int }
tuiRenderAndWait screen sub =
    BackendTask.Internal.Request.request
        { name = "tui-render-and-wait"
        , body =
            BackendTask.Http.jsonBody
                (Encode.object
                    [ ( "screen", Tui.encodeScreen screen )
                    , ( "interests", Sub.getInterests sub )
                    ]
                )
        , expect =
            BackendTask.Http.expectJson
                (Decode.map2 (\evts wh -> { events = evts, width = wh.width, height = wh.height })
                    (Decode.oneOf
                        [ Decode.field "events" (Decode.list Decode.value)
                        , Decode.field "event" Decode.value |> Decode.map List.singleton
                        ]
                    )
                    (Decode.map2 (\w h -> { width = w, height = h })
                        (Decode.field "width" Decode.int)
                        (Decode.field "height" Decode.int)
                    )
                )
        }


{-| Exit TUI mode: restore terminal, show cursor, exit alternate screen.
-}
tuiExit : Int -> BackendTask FatalError ()
tuiExit code =
    BackendTask.Internal.Request.request
        { name = "tui-exit"
        , body =
            BackendTask.Http.jsonBody
                (Encode.int code)
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }



-- THE LOOP


processEffectsThenRenderAndWait :
    { init : data -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Sub msg
    }
    -> Context
    -> model
    -> Effect msg
    -> BackendTask FatalError ()
processEffectsThenRenderAndWait config context model effect =
    -- elm-review: known-unoptimized-recursion
    Effect.toBackendTask effect
        |> BackendTask.andThen
            (\result ->
                case result of
                    Effect.EffectDone ->
                        renderAndWait config context model

                    Effect.EffectMsg msg ->
                        let
                            ( newModel, newEffect ) =
                                config.update msg model
                        in
                        processEffectsThenRenderAndWait config context newModel newEffect

                    Effect.EffectExit code ->
                        tuiExit code
                            |> BackendTask.andThen
                                (\() ->
                                    if code /= 0 then
                                        BackendTask.fail
                                            (FatalError.build
                                                { title = "TUI exited with code " ++ String.fromInt code
                                                , body = ""
                                                }
                                            )

                                    else
                                        BackendTask.succeed ()
                                )
            )


renderAndWait :
    { init : data -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Sub msg
    }
    -> Context
    -> model
    -> BackendTask FatalError ()
renderAndWait config context model =
    -- elm-review: known-unoptimized-recursion
    let
        screen : Screen
        screen =
            config.view context model

        sub : Sub msg
        sub =
            config.subscriptions model
    in
    tuiRenderAndWait screen sub
        |> BackendTask.andThen
            (\response ->
                let
                    newContext : Context
                    newContext =
                        { width = response.width
                        , height = response.height
                        }
                in
                -- Process all batched events through update sequentially
                -- (like gocui's processRemainingEvents drain), then render once
                processBatchedEvents config sub newContext model response.events
            )


{-| Process a list of raw events through update, folding the model.
Only the final model gets rendered.
-}
processBatchedEvents :
    { init : data -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Sub msg
    }
    -> Sub msg
    -> Context
    -> model
    -> List Decode.Value
    -> BackendTask FatalError ()
processBatchedEvents config sub context model events =
    case events of
        [] ->
            renderAndWait config context model

        rawValue :: rest ->
            let
                rawEvent : Sub.RawEvent
                rawEvent =
                    decodeRawEvent rawValue
            in
            case rawEvent of
                Sub.RawResize _ ->
                    -- Apply resize context, continue processing
                    processBatchedEvents config sub context model rest

                _ ->
                    case Sub.routeEvent sub rawEvent of
                        Just msg ->
                            let
                                ( newModel, newEffect ) =
                                    config.update msg model
                            in
                            case rest of
                                [] ->
                                    -- Last event — process effects and render
                                    processEffectsThenRenderAndWait config context newModel newEffect

                                _ ->
                                    -- More events queued — fold model, skip effects for now
                                    processBatchedEvents config sub context newModel rest

                        Nothing ->
                            processBatchedEvents config sub context model rest


{-| Decode a raw JSON event into a RawEvent.
-}
decodeRawEvent : Decode.Value -> Sub.RawEvent
decodeRawEvent value =
    case Decode.decodeValue Sub.decodeRawEvent value of
        Ok event ->
            event

        Err _ ->
            -- If we can't decode, treat as a tick (will be ignored if not subscribed)
            Sub.RawTick
