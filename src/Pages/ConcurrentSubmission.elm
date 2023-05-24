module Pages.ConcurrentSubmission exposing
    ( ConcurrentSubmission, Status(..)
    , map
    )

{-| When you render a `Form` with the [`Pages.Form.withConcurrent`](Pages-Form#withConcurrent) `Option`, the state of in-flight and completed submissions will be available
from your `Route` module through `app.concurrentSubmissions` as a `Dict String (ConcurrentSubmission (Maybe Action))`.

You can use this state to declaratively derive Pending UI or Optimistic UI from your pending submissions (without managing the state in your `Model`, since `elm-pages`
manages form submission state for you).

You can [see the full-stack TodoMVC example](https://github.com/dillonkearns/elm-pages-v3-beta/blob/master/examples/todos/app/Route/Visibility__.elm) for a complete example of deriving Pending UI state from `app.concurrentSubmissions`.

For example, this how the TodoMVC example derives the list of new items that are being created (but are still pending).

    view :
        App Data ActionData RouteParams
        -> Shared.Model
        -> Model
        -> View (PagesMsg Msg)
    view app shared model =
        let
            pendingActions : List Action
            pendingActions =
                app.concurrentSubmissions
                    |> Dict.values
                    |> List.filterMap
                        (\{ status, payload } ->
                            case status of
                                Pages.ConcurrentSubmission.Complete _ ->
                                    Nothing

                                _ ->
                                    allForms
                                        |> Form.Handler.run payload.fields
                                        |> Form.toResult
                                        |> Result.toMaybe
                        )

            newPendingItems : List Entry
            newPendingItems =
                pendingActions
                    |> List.filterMap
                        (\submission ->
                            case submission of
                                Add description ->
                                    Just
                                        { description = description
                                        , completed = False
                                        , id = ""
                                        , isPending = True
                                        }

                                _ ->
                                -- `newPendingItems` only cares about pending Add actions. Other values will use
                                -- pending submissions for other types of Actions.
                                    Nothing
                        )
        in
        itemsView app newPendingItems

        allForms : Form.Handler.Handler String Action
        allForms =
                |> Form.Handler.init Add addItemForm
                -- |> Form.Handler.with ...


        type Action
            = UpdateEntry ( String, String )
            | Add String
            | Delete String
            | DeleteComplete
            | Check ( Bool, String )
            | CheckAll Bool

@docs ConcurrentSubmission, Status

@docs map

-}

import Pages.FormData exposing (FormData)
import Time


{-| -}
type alias ConcurrentSubmission actionData =
    { status : Status actionData
    , payload : FormData
    , initiatedAt : Time.Posix
    }


{-| The status of a `ConcurrentSubmission`.

  - `Submitting` - The submission is in-flight.
  - `Reloading` - The submission has completed, and the page is now reloading the `Route`'s `data` to reflect the new state. The `actionData` holds any data returned from the `Route`'s `action`.
  - `Complete` - The submission has completed, and the `Route`'s `data` has since reloaded so the state reflects the refreshed state after completing this specific form submission. The `actionData` holds any data returned from the `Route`'s `action`.

-}
type Status actionData
    = Submitting
    | Reloading actionData
    | Complete actionData


{-| `map` a `ConcurrentSubmission`. Not needed for most high-level cases since this state is managed by the `elm-pages` framework for you.
-}
map : (a -> b) -> ConcurrentSubmission a -> ConcurrentSubmission b
map mapFn fetcherState =
    { status = mapStatus mapFn fetcherState.status
    , payload = fetcherState.payload
    , initiatedAt = fetcherState.initiatedAt
    }


mapStatus : (a -> b) -> Status a -> Status b
mapStatus mapFn fetcherSubmitStatus =
    case fetcherSubmitStatus of
        Submitting ->
            Submitting

        Reloading value ->
            Reloading (mapFn value)

        Complete value ->
            Complete (mapFn value)
