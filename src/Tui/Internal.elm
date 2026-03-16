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


{-| Send a rendered screen to the JS runtime for display.
-}
tuiRender : Screen -> BackendTask FatalError ()
tuiRender screen =
    BackendTask.Internal.Request.request
        { name = "tui-render"
        , body =
            BackendTask.Http.jsonBody
                (Tui.encodeScreen screen)
        , expect = BackendTask.Http.expectJson (Decode.succeed ())
        }


{-| Wait for the next terminal event. Sends subscription interests so the JS
side knows what to listen for. Returns the event and current terminal size.
-}
tuiWaitEvent : Sub msg -> BackendTask FatalError { event : Decode.Value, width : Int, height : Int }
tuiWaitEvent sub =
    BackendTask.Internal.Request.request
        { name = "tui-wait-event"
        , body =
            BackendTask.Http.jsonBody
                (Sub.getInterests sub)
        , expect =
            BackendTask.Http.expectJson
                (Decode.map3 (\e w h -> { event = e, width = w, height = h })
                    (Decode.field "event" Decode.value)
                    (Decode.field "width" Decode.int)
                    (Decode.field "height" Decode.int)
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
    in
    tuiRender screen
        |> BackendTask.andThen
            (\() ->
                let
                    sub : Sub msg
                    sub =
                        config.subscriptions model
                in
                tuiWaitEvent sub
                    |> BackendTask.andThen
                        (\response ->
                            let
                                newContext : Context
                                newContext =
                                    { width = response.width
                                    , height = response.height
                                    }

                                rawEvent : Sub.RawEvent
                                rawEvent =
                                    decodeRawEvent response.event
                            in
                            case rawEvent of
                                Sub.RawResize _ ->
                                    -- Resize is framework-managed: just re-render with new context
                                    renderAndWait config newContext model

                                _ ->
                                    case Sub.routeEvent sub rawEvent of
                                        Just msg ->
                                            let
                                                ( newModel, newEffect ) =
                                                    config.update msg model
                                            in
                                            processEffectsThenRenderAndWait config newContext newModel newEffect

                                        Nothing ->
                                            renderAndWait config newContext model
                        )
            )


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
