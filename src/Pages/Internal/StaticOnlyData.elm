module Pages.Internal.StaticOnlyData exposing (StaticOnlyData(..), placeholder, unwrap)

{-| Internal module for static data wrapper.

This is used internally by elm-pages to wrap staticData values. The wrapper
prevents users from accidentally accessing staticData in contexts where it
shouldn't be available (like during client-side rendering).

-}


{-| Opaque wrapper for static-only data.

Has two variants:

  - `StaticOnlyData a` - contains actual static data (used server-side/CLI)
  - `Placeholder` - empty placeholder (used client-side where static data is not available)

-}
type StaticOnlyData a
    = StaticOnlyData a
    | Placeholder


{-| Placeholder value for contexts where staticData is not available.
This is used on the client side where static data doesn't exist.
The value is never actually accessed - static regions are adopted from pre-rendered HTML,
and the elm-review codemod transforms View.staticView calls to View.adopt before any
code path that would unwrap this placeholder can execute.
-}
placeholder : StaticOnlyData staticData
placeholder =
    Placeholder


{-| Unwrap static data (internal use only).

The Placeholder case uses self-referential recursion to satisfy the type checker.
This is safe because:

1.  The elm-review codemod transforms View.staticView to View.adopt on the client
2.  The code that would call unwrap on a Placeholder is eliminated by DCE
3.  If somehow called, it would loop infinitely (indicating a programmer error)

-}
unwrap : StaticOnlyData a -> a
unwrap staticOnlyData =
    case staticOnlyData of
        StaticOnlyData a ->
            a

        Placeholder ->
            -- This branch is never executed in production.
            -- DCE eliminates all code paths that could reach here.
            -- Self-reference satisfies the type checker without Debug.todo.
            unwrap Placeholder
