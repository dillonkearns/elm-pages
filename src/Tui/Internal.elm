module Tui.Internal exposing (encodeScreen, run)

{-| Internal TUI loop implementation. Not exposed to users.
-}

import BackendTask exposing (BackendTask)
import BackendTask.Http
import BackendTask.Internal.Request
import FatalError exposing (FatalError)
import Json.Decode as Decode
import Json.Encode as Encode
import Ansi.Color
import Tui exposing (Attribute(..), ColorProfile(..), Context, Screen)
import Tui.Screen.Internal as ScreenInternal
import Tui.Effect as Effect exposing (Effect)
import Tui.Sub as Sub exposing (Sub)


decodeColorProfile : Decode.Decoder ColorProfile
decodeColorProfile =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "truecolor" ->
                        Decode.succeed TrueColor

                    "256" ->
                        Decode.succeed Color256

                    "16" ->
                        Decode.succeed Color16

                    "mono" ->
                        Decode.succeed Mono

                    _ ->
                        Decode.succeed Color16
            )


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

                    ( modelWithContext, contextEffect ) =
                        applyContextUpdate config.update
                            (config.subscriptions initialModel)
                            context
                            initialModel
                in
                processEffectsThenRenderAndWait config context modelWithContext
                    (Effect.batch [ initialEffect, contextEffect ])
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
                (Decode.map3 (\w h cp -> { width = w, height = h, colorProfile = cp })
                    (Decode.field "width" Decode.int)
                    (Decode.field "height" Decode.int)
                    (Decode.field "colorProfile" decodeColorProfile)
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
                    ([ ( "screen", encodeScreen screen )
                     , ( "interests", Sub.getInterests sub )
                     ]
                        ++ (case Sub.getTickInterval sub of
                                Just interval ->
                                    [ ( "tickInterval", Encode.float interval ) ]

                                Nothing ->
                                    []
                           )
                    )
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
        |> BackendTask.quiet
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
                        , colorProfile = context.colorProfile
                        }

                    -- Fire context change through subscription if dimensions changed
                    ( modelAfterContext, contextEffects ) =
                        if newContext.width /= context.width || newContext.height /= context.height then
                            applyContextUpdate config.update sub newContext model
                                |> Tuple.mapSecond effectToList

                        else
                            ( model, [] )
                in
                processBatchedEventsHelp config sub newContext modelAfterContext contextEffects response.events
            )


{-| Process a list of raw events through update, folding the model.
All effects are accumulated and run after the final event.
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
    processBatchedEventsHelp config sub context model [] events


processBatchedEventsHelp :
    { init : data -> ( model, Effect msg )
    , update : msg -> model -> ( model, Effect msg )
    , view : Context -> model -> Screen
    , subscriptions : model -> Sub msg
    }
    -> Sub msg
    -> Context
    -> model
    -> List (Effect msg)
    -> List Decode.Value
    -> BackendTask FatalError ()
processBatchedEventsHelp config sub context model accEffects events =
    -- elm-review: known-unoptimized-recursion
    case events of
        [] ->
            case accEffects of
                [] ->
                    renderAndWait config context model

                _ ->
                    processEffectsThenRenderAndWait config context model
                        (Effect.batch (List.reverse accEffects))

        rawValue :: rest ->
            let
                rawEvent : Sub.RawEvent
                rawEvent =
                    decodeRawEvent rawValue
            in
            case rawEvent of
                Sub.RawResize _ ->
                    -- Apply resize context, continue processing
                    processBatchedEventsHelp config sub context model accEffects rest

                _ ->
                    case Sub.routeEvent sub rawEvent of
                        Just msg ->
                            let
                                ( newModel, newEffect ) =
                                    config.update msg model
                            in
                            processBatchedEventsHelp config sub context newModel (newEffect :: accEffects) rest

                        Nothing ->
                            processBatchedEventsHelp config sub context model accEffects rest


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


applyContextUpdate :
    (msg -> model -> ( model, Effect msg ))
    -> Sub msg
    -> Context
    -> model
    -> ( model, Effect msg )
applyContextUpdate update sub context model =
    case Sub.routeEvent sub (Sub.RawContext { width = context.width, height = context.height }) of
        Just msg ->
            update msg model

        Nothing ->
            ( model, Effect.none )


effectToList : Effect msg -> List (Effect msg)
effectToList effect =
    case effect of
        Effect.None ->
            []

        _ ->
            [ effect ]



-- ENCODING (for sending to JS runtime)


encodeScreen : Screen -> Encode.Value
encodeScreen screen =
    ScreenInternal.flattenToSpanLines styleToFlatStyle screen
        |> Encode.list
            (\spanLine ->
                Encode.list encodeSpan spanLine
            )


styleToFlatStyle : Tui.Style -> ScreenInternal.FlatStyle
styleToFlatStyle s =
    let
        def : ScreenInternal.FlatStyle
        def =
            ScreenInternal.defaultFlatStyle

        base : ScreenInternal.FlatStyle
        base =
            { def
                | foreground = s.fg
                , background = s.bg
                , hyperlink = s.hyperlink
            }
    in
    List.foldl applyAttr base s.attributes


applyAttr : Attribute -> ScreenInternal.FlatStyle -> ScreenInternal.FlatStyle
applyAttr attr flatStyle =
    case attr of
        Bold ->
            { flatStyle | bold = True }

        Dim ->
            { flatStyle | dim = True }

        Italic ->
            { flatStyle | italic = True }

        Underline ->
            { flatStyle | underline = True }

        Strikethrough ->
            { flatStyle | strikethrough = True }

        Inverse ->
            { flatStyle | inverse = True }


encodeSpan : ScreenInternal.Span -> Encode.Value
encodeSpan span =
    Encode.object
        [ ( "text", Encode.string span.text )
        , ( "style", encodeFlatStyle span.style )
        ]


encodeFlatStyle : ScreenInternal.FlatStyle -> Encode.Value
encodeFlatStyle flatStyle =
    Encode.object
        (List.filterMap identity
            [ if flatStyle.bold then
                Just ( "bold", Encode.bool True )

              else
                Nothing
            , if flatStyle.dim then
                Just ( "dim", Encode.bool True )

              else
                Nothing
            , if flatStyle.italic then
                Just ( "italic", Encode.bool True )

              else
                Nothing
            , if flatStyle.underline then
                Just ( "underline", Encode.bool True )

              else
                Nothing
            , if flatStyle.strikethrough then
                Just ( "strikethrough", Encode.bool True )

              else
                Nothing
            , if flatStyle.inverse then
                Just ( "inverse", Encode.bool True )

              else
                Nothing
            , flatStyle.foreground |> Maybe.map (\c -> ( "foreground", encodeColor c ))
            , flatStyle.background |> Maybe.map (\c -> ( "background", encodeColor c ))
            , flatStyle.hyperlink |> Maybe.map (\url -> ( "hyperlink", Encode.string url ))
            ]
        )


encodeColor : Ansi.Color.Color -> Encode.Value
encodeColor ansiColor =
    case ansiColor of
        Ansi.Color.Black ->
            Encode.string "black"

        Ansi.Color.Red ->
            Encode.string "red"

        Ansi.Color.Green ->
            Encode.string "green"

        Ansi.Color.Yellow ->
            Encode.string "yellow"

        Ansi.Color.Blue ->
            Encode.string "blue"

        Ansi.Color.Magenta ->
            Encode.string "magenta"

        Ansi.Color.Cyan ->
            Encode.string "cyan"

        Ansi.Color.White ->
            Encode.string "white"

        Ansi.Color.BrightBlack ->
            Encode.string "brightBlack"

        Ansi.Color.BrightRed ->
            Encode.string "brightRed"

        Ansi.Color.BrightGreen ->
            Encode.string "brightGreen"

        Ansi.Color.BrightYellow ->
            Encode.string "brightYellow"

        Ansi.Color.BrightBlue ->
            Encode.string "brightBlue"

        Ansi.Color.BrightMagenta ->
            Encode.string "brightMagenta"

        Ansi.Color.BrightCyan ->
            Encode.string "brightCyan"

        Ansi.Color.BrightWhite ->
            Encode.string "brightWhite"

        Ansi.Color.Custom256 { color } ->
            Encode.object [ ( "color256", Encode.int color ) ]

        Ansi.Color.CustomTrueColor { red, green, blue } ->
            Encode.object
                [ ( "r", Encode.int red )
                , ( "g", Encode.int green )
                , ( "b", Encode.int blue )
                ]
