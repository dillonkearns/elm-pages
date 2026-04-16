module CoreHelperTests exposing (suite)

import BackendTask
import Expect
import Test exposing (Test, describe, test)
import Test.BackendTask as BackendTaskTest
import Tui
import Tui.Effect as Effect exposing (Effect)
import Tui.Screen
import Tui.Sub
import Tui.Test as TuiTest


suite : Test
suite =
    describe "Core test helpers"
        [ describe "pressKeyN"
            [ test "pressKeyN 3 'j' advances counter by 3" <|
                \() ->
                    counterApp
                        |> TuiTest.pressKeyN 3 'j'
                        |> TuiTest.ensureViewHas "count: 3"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "pressKeyN 0 does nothing" <|
                \() ->
                    counterApp
                        |> TuiTest.pressKeyN 0 'j'
                        |> TuiTest.ensureViewHas "count: 0"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "pressKeyN 1 is same as pressKey" <|
                \() ->
                    counterApp
                        |> TuiTest.pressKeyN 1 'j'
                        |> TuiTest.ensureViewHas "count: 1"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "scrollDownN / scrollUpN"
            [ test "scrollDownN 5 scrolls down 5 times" <|
                \() ->
                    scrollApp
                        |> TuiTest.scrollDownN 5 { row = 1, col = 1 }
                        |> TuiTest.ensureViewHas "scrolled: 5"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "scrollUpN 3 scrolls up 3 times" <|
                \() ->
                    scrollApp
                        |> TuiTest.scrollDownN 5 { row = 1, col = 1 }
                        |> TuiTest.scrollUpN 3 { row = 1, col = 1 }
                        |> TuiTest.ensureViewHas "scrolled: 2"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "scrollDownN 0 does nothing" <|
                \() ->
                    scrollApp
                        |> TuiTest.scrollDownN 0 { row = 1, col = 1 }
                        |> TuiTest.ensureViewHas "scrolled: 0"
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        , describe "ensureModel"
            [ test "can inspect model directly" <|
                \() ->
                    counterApp
                        |> TuiTest.pressKeyN 5 'j'
                        |> TuiTest.ensureModel
                            (\model -> Expect.equal 5 model.count)
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            , test "fails when model expectation fails" <|
                \() ->
                    counterApp
                        |> TuiTest.pressKeyN 3 'j'
                        |> TuiTest.ensureModel
                            (\model -> Expect.equal 3 model.count)
                        |> TuiTest.expectRunning
                        |> TuiTest.done
            ]
        ]



-- Counter app: 'j' increments, 'k' decrements
-- Uses Maybe msg pattern since onKeyPress returns Sub (Maybe msg)


type alias CounterModel =
    { count : Int }


type CounterMsg
    = Increment
    | Decrement


counterApp : TuiTest.TuiTest CounterModel (Maybe CounterMsg)
counterApp =
    TuiTest.start BackendTaskTest.init
        { data = BackendTask.succeed ()
        , init = \() -> ( { count = 0 }, Effect.none )
        , update = counterUpdate
        , view = counterView
        , subscriptions = \_ -> Tui.Sub.onKeyPress counterKeyHandler
        }


counterKeyHandler : Tui.Sub.KeyEvent -> Maybe CounterMsg
counterKeyHandler event =
    case event.key of
        Tui.Sub.Character 'j' ->
            Just Increment

        Tui.Sub.Character 'k' ->
            Just Decrement

        _ ->
            Nothing


counterUpdate : Maybe CounterMsg -> CounterModel -> ( CounterModel, Effect (Maybe CounterMsg) )
counterUpdate msg model =
    case msg of
        Just Increment ->
            ( { model | count = model.count + 1 }, Effect.none )

        Just Decrement ->
            ( { model | count = model.count - 1 }, Effect.none )

        Nothing ->
            ( model, Effect.none )


counterView : Tui.Context -> CounterModel -> Tui.Screen.Screen
counterView _ model =
    Tui.Screen.text ("count: " ++ String.fromInt model.count)



-- Scroll app: tracks scroll events


type alias ScrollModel =
    { scrolled : Int }


type ScrollMsg
    = ScrolledDown
    | ScrolledUp


scrollApp : TuiTest.TuiTest ScrollModel (Maybe ScrollMsg)
scrollApp =
    TuiTest.start BackendTaskTest.init
        { data = BackendTask.succeed ()
        , init = \() -> ( { scrolled = 0 }, Effect.none )
        , update = scrollUpdate
        , view = scrollView
        , subscriptions =
            \_ ->
                Tui.Sub.onMouse
                    (\event ->
                        case event of
                            Tui.Sub.ScrollDown _ ->
                                Just ScrolledDown

                            Tui.Sub.ScrollUp _ ->
                                Just ScrolledUp

                            _ ->
                                Nothing
                    )
        }


scrollUpdate : Maybe ScrollMsg -> ScrollModel -> ( ScrollModel, Effect (Maybe ScrollMsg) )
scrollUpdate msg model =
    case msg of
        Just ScrolledDown ->
            ( { model | scrolled = model.scrolled + 1 }, Effect.none )

        Just ScrolledUp ->
            ( { model | scrolled = model.scrolled - 1 }, Effect.none )

        Nothing ->
            ( model, Effect.none )


scrollView : Tui.Context -> ScrollModel -> Tui.Screen.Screen
scrollView _ model =
    Tui.Screen.text ("scrolled: " ++ String.fromInt model.scrolled)
