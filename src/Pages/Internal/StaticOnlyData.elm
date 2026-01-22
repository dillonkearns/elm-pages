module Pages.Internal.StaticOnlyData exposing
    ( StaticOnlyData(..)
    , placeholder
    , unwrap
    )

{-| Internal module for StaticOnlyData. Exposes constructors for framework use.

**Do not use this module directly.** Use `StaticOnlyData` instead.

@docs StaticOnlyData, placeholder, unwrap

-}


{-| Opaque wrapper for data that should only be used in static regions.

This type has two variants:

  - `StaticOnlyData a` - contains real data (used at build time)
  - `ClientPlaceholder` - empty placeholder (used on client after decoding)

-}
type StaticOnlyData a
    = StaticOnlyData a
    | ClientPlaceholder


{-| Create a placeholder value for client-side decoding.

This is used by generated decoders. The placeholder is safe because
`Static.view` calls are transformed to `View.adopt` by elm-review,
so the placeholder is never unwrapped on the client.

-}
placeholder : StaticOnlyData a
placeholder =
    ClientPlaceholder


{-| Unwrap the static data. Only call this at build time.

On the client, this would hit the unreachable branch if called with
`ClientPlaceholder`. But `Static.view` is transformed to `View.adopt`
by elm-review, so this function is never called on the client.

-}
unwrap : StaticOnlyData a -> a
unwrap data =
    case data of
        StaticOnlyData a ->
            a

        ClientPlaceholder ->
            unreachable ()


{-| Infinitely recursive function that can return any type.

This compiles with --optimize (unlike Debug.todo) and is safe as long as
it's never actually called. It's placed inside the ClientPlaceholder branch
of unwrap, which is never executed on the client.

-}
unreachable : () -> a
unreachable () =
    unreachable ()
