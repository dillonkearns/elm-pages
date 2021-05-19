module Pages.Flags exposing (Flags(..))

{-|

@docs Flags

-}

import Json.Decode


{-| elm-pages apps run in two different contexts

1.  In the browser (like a regular Elm app)
2.  In pre-render mode. For example when you run `elm-pages build`, there is no browser involved, it just runs Elm directly.

You can pass in Flags and use them in your `Shared.init` function. You can store data in your `Shared.Model` from these flags and then access it across any page.

You will need to handle the `PreRender` case with no flags value because there is no browser to get flags from. For example, say you wanted to get the
current user's Browser window size and pass it in as a flag. When that page is pre-rendered, you need to decide on a value to use for the window size
since there is no window (the user hasn't requested the page yet, and the page isn't even loaded in a Browser window yet).

-}
type Flags
    = BrowserFlags Json.Decode.Value
    | PreRenderFlags
