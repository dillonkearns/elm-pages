module Pages.Msg exposing
    ( Msg
    , fromMsg
    , map, noOp
    , onSubmit
    )

{-| In `elm-pages`, Route modules have their own `Msg` type which can be used like a normal TEA (The Elm Architecture) app.
But the `Msg` defined in a `Route` module is wrapped in the `Pages.Msg.Msg` type.

@docs Msg

You can wrap your Route Module's `Msg` using `fromMsg`.

@docs fromMsg

@docs map, noOp

@docs onSubmit

-}

import Html exposing (Attribute)
import Pages.Internal.Msg


{-| -}
type alias Msg userMsg =
    Pages.Internal.Msg.Msg userMsg


{-|

    type Msg
        = ToggleMenu

    view :
        Maybe PageUrl
        -> Shared.Model
        -> Model
        -> StaticPayload Data ActionData RouteParams
        -> View (Pages.Msg.Msg Msg)
    view maybeUrl sharedModel model app =
        { title = "My Page"
        , view =
            [ button
                -- we need to wrap our Route module's `Msg` here so we have a `Pages.Msg.Msg Msg`
                [ onClick (Pages.Msg.fromMsg ToggleMenu) ]
                []

            -- `Form.renderHtml` gives us `Html (Pages.Msg.Msg msg)`, so we don't need to wrap its Msg type
            , logoutForm
                |> Form.toDynamicTransition "logout"
                |> Form.withOnSubmit (\_ -> NewItemSubmitted)
                |> Form.renderHtml [] (\_ -> Nothing) app Nothing
            ]
        }

-}
fromMsg : userMsg -> Msg userMsg
fromMsg userMsg =
    Pages.Internal.Msg.UserMsg userMsg


{-| A Msg that is handled by the elm-pages framework and does nothing. Helpful for when you don't want to register a callback.

    import Browser.Dom as Dom
    import Pages.Msg
    import Task

    resetViewport : Cmd (Pages.Msg.Msg msg)
    resetViewport =
        Dom.setViewport 0 0
            |> Task.perform (\() -> Pages.Msg.noOp)

-}
noOp : Msg userMsg
noOp =
    Pages.Internal.Msg.NoOp


{-| -}
map : (a -> b) -> Msg a -> Msg b
map mapFn msg =
    Pages.Internal.Msg.map mapFn msg


{-| -}
onSubmit : Attribute (Msg userMsg)
onSubmit =
    Pages.Internal.Msg.onSubmit
