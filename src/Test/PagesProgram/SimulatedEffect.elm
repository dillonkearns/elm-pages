module Test.PagesProgram.SimulatedEffect exposing
    ( SimulatedEffect(..)
    , none, batch, dispatchMsg, setField, submitFetcher
    , map
    )

{-| Simulated effects for testing. These parallel Elm's `Cmd` type
but are inspectable by the test framework.

Use these with [`Effect.testPerform`](Effect#testPerform) to decompose
your `Effect` type into something the test framework can process.

    import Test.PagesProgram.SimulatedEffect as SimulatedEffect

    -- In your Effect module:
    testPerform : Effect msg -> SimulatedEffect msg
    testPerform effect =
        case effect of
            None ->
                SimulatedEffect.none

            Cmd _ ->
                -- Opaque Cmds cannot be simulated. Use simulateMsg
                -- in your test to inject the message manually.
                SimulatedEffect.none

            Batch list ->
                SimulatedEffect.batch (List.map testPerform list)

            SendMsg msg ->
                SimulatedEffect.dispatchMsg msg

@docs SimulatedEffect

@docs none, batch, dispatchMsg, setField, submitFetcher

@docs map

-}

import Pages.Fetcher


{-| A simulated effect that the test framework can inspect and execute.

  - `None` -- no effect
  - `Batch` -- multiple effects
  - `DispatchMsg msg` -- dispatch a message through the update cycle
  - `SetField` -- set a form field value
  - `SubmitFetcher` -- submit a fetcher (concurrent form submission)

-}
type SimulatedEffect msg
    = None
    | Batch (List (SimulatedEffect msg))
    | DispatchMsg msg
    | SetField { formId : String, name : String, value : String }
    | SubmitFetcher (Pages.Fetcher.Fetcher msg)


{-| No effect. Parallels `Effect.none`.

Also use this for opaque `Cmd` values that cannot be simulated.
Use [`simulateMsg`](Test-PagesProgram#simulateMsg) in your test to
inject the message that the `Cmd` would have produced.

-}
none : SimulatedEffect msg
none =
    None


{-| Combine multiple simulated effects. Parallels `Effect.batch`.
-}
batch : List (SimulatedEffect msg) -> SimulatedEffect msg
batch =
    Batch


{-| Dispatch a message through the program's update cycle. This is the
test-simulatable equivalent of `Effect.sendMsg`.

    testPerform effect =
        case effect of
            SendMsg msg ->
                SimulatedEffect.dispatchMsg msg

-}
dispatchMsg : msg -> SimulatedEffect msg
dispatchMsg =
    DispatchMsg


{-| Set a form field value. Parallels `Effect.setField`.
-}
setField : { formId : String, name : String, value : String } -> SimulatedEffect msg
setField =
    SetField


{-| Submit a fetcher for concurrent form submission. Parallels `Effect.submitFetcher`.
-}
submitFetcher : Pages.Fetcher.Fetcher msg -> SimulatedEffect msg
submitFetcher =
    SubmitFetcher


{-| Transform the messages produced by a simulated effect.
-}
map : (a -> msg) -> SimulatedEffect a -> SimulatedEffect msg
map f effect =
    case effect of
        None ->
            None

        Batch effects ->
            Batch (List.map (map f) effects)

        DispatchMsg msg ->
            DispatchMsg (f msg)

        SetField info ->
            SetField info

        SubmitFetcher fetcher ->
            SubmitFetcher (Pages.Fetcher.map f fetcher)
