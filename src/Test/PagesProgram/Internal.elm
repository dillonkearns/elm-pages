module Test.PagesProgram.Internal exposing
    ( Snapshot
    , StepKind(..)
    , TargetSelector(..)
    , NetworkEntry
    , NetworkStatus(..)
    , NetworkSource(..)
    , FetcherEntry
    , FetcherStatus(..)
    )

{-| Internal types used by the visual test runner (Viewer). These are not
part of the public API and should not be relied upon by end users.

@docs Snapshot, StepKind, TargetSelector, NetworkEntry, NetworkStatus, FetcherEntry, FetcherStatus

-}

import Html exposing (Html)
import Test.PagesProgram.Selector.Internal exposing (AssertionSelector)


{-| A snapshot of the program state at a point in the test pipeline.
-}
type alias Snapshot =
    { label : String
    , title : String
    , body : List (Html Never)
    , rerender : () -> { title : String, body : List (Html Never) }
    , hasPendingEffects : Bool
    , modelState : Maybe String
    , stepKind : StepKind
    , browserUrl : Maybe String
    , errorMessage : Maybe String
    , pendingEffects : List String
    , networkLog : List NetworkEntry
    , targetElement : Maybe TargetSelector
    , assertionSelectors : List AssertionSelector
    , scopeSelectors : List (List AssertionSelector)
    , fetcherLog : List FetcherEntry
    , groupLabel : Maybe String
    }


{-| The kind of step that produced a snapshot.
-}
type StepKind
    = Start
    | Interaction
    | Assertion
    | EffectResolution
    | Error


{-| An HTTP request or custom port entry in the network log.
-}
type alias NetworkEntry =
    { method : String
    , url : String
    , status : NetworkStatus
    , stepIndex : Int
    , portName : Maybe String
    , responsePreview : Maybe String
    , source : NetworkSource
    , requestBody : Maybe String
    , requestHeaders : List ( String, String )
    }


{-| Whether an HTTP request was stubbed or is pending.
-}
type NetworkStatus
    = Stubbed
    | Pending


{-| Whether the request originated from a BackendTask (server-side) or
from a client-side TEA Effect.
-}
type NetworkSource
    = Backend
    | Frontend


{-| Describes which DOM element a test interaction targeted.
-}
type TargetSelector
    = ByTagAndText String String
    | ByFormField String String
    | ByLabelText String
    | ById String
    | ByTag String
    | BySelectors (List AssertionSelector)


{-| A snapshot of an in-flight fetcher's state.
-}
type alias FetcherEntry =
    { id : String
    , status : FetcherStatus
    , fields : List ( String, String )
    , action : String
    , method : String
    }


{-| The status of a fetcher submission.
-}
type FetcherStatus
    = FetcherSubmitting
    | FetcherReloading
    | FetcherComplete
