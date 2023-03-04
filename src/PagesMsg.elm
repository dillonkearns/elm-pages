module PagesMsg exposing
    ( PagesMsg
    , fromMsg
    , map, noOp
    , onSubmit
    )

{-| In `elm-pages`, Route modules have their own `Msg` type which can be used like a normal TEA (The Elm Architecture) app.
But the `Msg` defined in a `Route` module is wrapped in the `PagesMsg` type.

@docs PagesMsg

You can wrap your Route Module's `Msg` using `fromMsg`.

@docs fromMsg

@docs map, noOp

@docs onSubmit

-}

import Html exposing (Attribute)
import Pages.Internal.Msg


{-| -}
type alias PagesMsg userMsg =
    Pages.Internal.Msg.Msg userMsg


{-|

    import PagesMsg exposing (PagesMsg)

    type Msg
        = ToggleMenu

    view :
        Maybe PageUrl
        -> Shared.Model
        -> Model
        -> App Data ActionData RouteParams
        -> View (PagesMsg Msg)
    view maybeUrl sharedModel model app =
        { title = "My Page"
        , view =
            [ button
                -- we need to wrap our Route module's `Msg` here so we have a `PagesMsg Msg`
                [ onClick (PagesMsg.fromMsg ToggleMenu) ]
                []

            -- `Form.renderHtml` gives us `Html (PagesMsg msg)`, so we don't need to wrap its Msg type
            , logoutForm
                |> Form.withOnSubmit (\_ -> NewItemSubmitted)
                |> Form.renderHtml "logout" [] (\_ -> Nothing) app Nothing
            ]
        }

-}
fromMsg : userMsg -> PagesMsg userMsg
fromMsg userMsg =
    Pages.Internal.Msg.UserMsg userMsg


{-| A Msg that is handled by the elm-pages framework and does nothing. Helpful for when you don't want to register a callback.

    import Browser.Dom as Dom
    import PagesMsg exposing (PagesMsg)
    import Task

    resetViewport : Cmd (PagesMsg msg)
    resetViewport =
        Dom.setViewport 0 0
            |> Task.perform (\() -> PagesMsg.noOp)

-}
noOp : PagesMsg userMsg
noOp =
    Pages.Internal.Msg.NoOp


{-| -}
map : (a -> b) -> PagesMsg a -> PagesMsg b
map mapFn msg =
    Pages.Internal.Msg.map mapFn msg


{-| -}
onSubmit : Attribute (PagesMsg userMsg)
onSubmit =
    Pages.Internal.Msg.onSubmit
