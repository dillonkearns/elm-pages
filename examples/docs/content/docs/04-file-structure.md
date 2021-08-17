---
description: TODO
---

# File Structure

With `elm-pages`, you don't define the central `Main.elm` entrypoint. That's defined under the hood by `elm-pages`.

It builds your app for you from these special files that you define:

`src/`

- [`View.elm`](/docs/file-structure#view.elm)
- [`Shared.elm`](/docs/file-structure#shared.elm)
- [`Api.elm`](/docs/file-structure#api.elm)
- [`Site.elm`](/docs/file-structure#site.elm)
- [`Page/`](/docs/file-structure#page-modules)

There is also a special `public/` folder that will directly copy assets without any processing.

- [`public/`](/docs/file-structure#public)

And entrypoint files for your CSS and JS.

- [`index.js`](/docs/file-structure#index.js)
- [`style.css`](/docs/file-structure#style.css)

## Page Modules

This folder is the core of your `elm-pages` app. Elm modules defined under `src/Page/` are what define the routes for your app. See [File-Based Routing](/docs/file-based-routing).

## `View.elm`

Defines the types for your application's `View msg` type.
Must expose

- A type called `View msg` (must have exactly one type variable)
- `map : (msg1 -> msg2) -> View msg1 -> View msg2`
- `placeholder : String -> View msg` - used in when you scaffold a new Page module with `elm-pages add MyRoute`

The `View msg` type is what individual `Page/` modules must return in their `view` functions.
So if you want to use `mdgriffith/elm-ui` in your `Page`'s `view` functions, you would update your module like this:

```elm
module View exposing (View, map, placeholder)

import Element exposing (Element)


type alias View msg =
    { title : String
    , body : List (Element msg)
    }


map : (msg1 -> msg2) -> View msg1 -> View msg2
map fn view =
    { title = view.title
    , body = List.map (Element.map fn) view.body
    }


placeholder : String -> View msg
placeholder moduleName =
    { title = "Placeholder"
    , body = [ Element.text moduleName ]
    }
```

`View msg` can be any type. For example, if you wanted to render your sites navbar
for home pages, and hide it for standalone landing pages, you could include that information in your `View msg` type.

```elm
type PageLayout
    = LandingPage
    | HomePage

type alias View msg =
    { title : String
    , body : List (PageView msg)
    , layout : PageLayout
    }
```

Then in your `Shared.elm` module, you would render based on that extra field.

## `Shared.elm`

This is where your site-wide layout goes. The `Shared.view` function receives the `view` from a
Page module, and can render it within a layout.

Must expose

- `template : SharedTemplate Msg Model StaticData msg`
- `Msg` - global `Msg`s across the whole app, like toggling a menu in the shared header view
- `Model` - shared state that persists between page navigations. This `Shared.Model` can be accessed by Page Templates.
- `SharedMsg`

## `Site.elm`

Defines global head tags and your manifest config.

Must expose

- `config : SiteConfig StaticData`

## `public`

Files in this folder are copied directly into `dist/` when you run `elm-pages build`. These files will also be served in the `elm-pages dev` server.

For example, if you had a file called `public/images/profile.jpg`, then you could access it at `http://localhost:1234/images/profile.jpg` in your dev server, or the corresponding path in your production domain.

## `index.js`

## `style.css`
