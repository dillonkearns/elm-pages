# File Structure

With `elm-pages`, you don't define the central `Main.elm` entrypoint. That's defined under the hood by `elm-pages`.

It builds your app for you from these special files that you define:

## `Shared.elm`

Must expose

- `template : SharedTemplate Msg Model StaticData msg`
- `Msg` - global `Msg`s across the whole app, like toggling a menu in the shared header view
- `Model` - shared state that persists between page navigations. This `Shared.Model` can be accessed by Page Templates.
- `SharedMsg` (todo - this needs to be documented better. Consider whether there could be an easier way to wire this in for users, too)

## `Site.elm`

Must expose

- `config : SiteConfig StaticData`

## `Document.elm`

Defines the types for your applications view.
Must expose

- A type called `Document msg` (must have exactly one type variable)
- `map : (msg1 -> msg2) -> Document msg1 -> Document msg2`

- `static/index.js` - same as previous `beta-index.js`
- `static/style.css` - same as previous `beta-style.css`
