module Tui.Spinner exposing (view, subscriptions)

{-| Stateless loading spinner animation. Not a full widget model — just a
rendering helper that cycles through `|`, `/`, `-`, `\` based on a tick
counter you manage in your model (like lazygit's spinner).

    -- In your model:
    type alias Model =
        { spinnerTick : Int
        , loading : Bool
        }

    -- In subscriptions:
    subscriptions model =
        if model.loading then
            Tui.Sub.batch
                [ Tui.Sub.onKeyPress KeyPressed
                , Tui.Spinner.subscriptions SpinnerTick
                ]
        else
            Tui.Sub.onKeyPress KeyPressed

    -- In update:
    SpinnerTick ->
        ( { model | spinnerTick = model.spinnerTick + 1 }, Effect.none )

    -- In view:
    if model.loading then
        Tui.concat
            [ Tui.text "Loading... "
            , Tui.Spinner.view model.spinnerTick
            ]
    else
        Tui.text "Done!"

@docs view, subscriptions

-}

import Tui
import Tui.Sub


{-| Render the spinner character for the current tick.
Uses lazygit's character set: `|`, `/`, `-`, `\`.
-}
view : Int -> Tui.Screen
view tick =
    let
        frames : List String
        frames =
            [ "|", "/", "-", "\\" ]

        index : Int
        index =
            modBy 4 tick
    in
    frames
        |> List.drop index
        |> List.head
        |> Maybe.withDefault "|"
        |> Tui.text


{-| Subscribe to spinner ticks (50ms interval). Only include this in
your subscriptions when a loading operation is in progress.
The message fires every 50ms to advance the spinner frame.
-}
subscriptions : msg -> Tui.Sub.Sub msg
subscriptions msg =
    Tui.Sub.every 50 msg
