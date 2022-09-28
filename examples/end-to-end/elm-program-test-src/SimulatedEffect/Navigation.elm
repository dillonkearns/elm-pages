module SimulatedEffect.Navigation exposing
    ( pushUrl, replaceUrl, back
    , load, reload, reloadAndSkipCache
    )

{-| This module parallels [elm/browsers's `Browser.Navigation` module](https://package.elm-lang.org/packages/elm/browser/1.0.1/Browser-Navigation).
_Pull requests are welcome to add any functions that are missing._

The functions here produce `SimulatedEffect`s instead of `Cmd`s, which are meant to be used
to help you implement the function to provide when using [`ProgramTest.withSimulatedEffects`](ProgramTest#withSimulatedEffects).


# Navigate within Page

@docs pushUrl, replaceUrl, back


# Navigate to other Pages

@docs load, reload, reloadAndSkipCache

-}

import ProgramTest exposing (SimulatedEffect)
import SimulatedEffect


{-| Change the URL, but do not trigger a page load.
This will add a new entry to the browser history.
-}
pushUrl : String -> SimulatedEffect msg
pushUrl =
    SimulatedEffect.PushUrl


{-| Change the URL, but do not trigger a page load.
This _will not_ add a new entry to the browser history.
-}
replaceUrl : String -> SimulatedEffect msg
replaceUrl =
    SimulatedEffect.ReplaceUrl


{-| Go back some number of pages.
-}
back : Int -> SimulatedEffect msg
back =
    SimulatedEffect.Back


{-| Leave the current page and load the given URL.
-}
load : String -> SimulatedEffect msg
load =
    SimulatedEffect.Load


{-| Reload the current page.
-}
reload : SimulatedEffect msg
reload =
    SimulatedEffect.Reload False


{-| Reload the current page without using the browser cache.
-}
reloadAndSkipCache : SimulatedEffect msg
reloadAndSkipCache =
    SimulatedEffect.Reload True
