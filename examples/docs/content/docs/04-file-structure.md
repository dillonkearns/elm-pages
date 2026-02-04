---
description: elm-pages has some special files that you define to build your app, including a file-based routing system.
---

# File Structure

With `elm-pages`, you don't define the central `Main.elm` entrypoint. That's defined under the hood by `elm-pages`.

It builds your app for you from these special files that you define:

`app/`

- [`View.elm`](/docs/file-structure#view.elm)
- [`Shared.elm`](/docs/file-structure#shared.elm)
- [`Api.elm`](/docs/file-structure#api.elm)
- [`Effect.elm`](/docs/file-structure#effect.elm)
- `ErrorPage.elm` (see [Error Page docs page](/docs/error-pages))
- [`Site.elm`](/docs/file-structure#site.elm)
- [`Route/`](/docs/file-structure#page-modules)

> Note: elm-pages uses the `app/` folder for Elm code that has a special meaning to the framework. It is recommended that you keep your own Elm code besides these special files in `src/` to make it clear which modules have special meaning for the framework.

There is also a special `public/` folder that will directly copy assets without any processing.

- [`public/`](/docs/file-structure#public)

And entrypoint files for your CSS and JS.

- [`index.ts`](/docs/file-structure#index.ts)
- [`style.css`](/docs/file-structure#style.css)

And a configuration file.

- [`elm-pages.config.mjs`](#elm-pages.config.mjs)

## Route Modules

This folder is the core of your `elm-pages` app. Elm modules defined under `app/Route/` are what define the routes for your app. See [File-Based Routing](/docs/file-based-routing).

## `View.elm`

Defines the types for your application's `View msg` type.
Must expose

- A type called `View msg` (must have exactly one type variable)
- `map : (msg1 -> msg2) -> View msg1 -> View msg2`

The `View msg` type is what individual `Route/` modules must return in their `view` functions.
So if you want to use `mdgriffith/elm-ui` in your `Route`'s `view` functions, you would update your module like this:

```elm
module View exposing (View, map)

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

## `Effect.elm`

`elm-pages` has built-in support for [the Effect Pattern](https://sporto.github.io/elm-patterns/architecture/effects.html).

If you want to use a `Cmd` directly instead of going through the level of indirection of an Effect, you can use `Effect.fromCmd : Cmd msg -> Effect msg`.
There's nothing wrong with using this if it suits your needs, the Effect pattern is there in case you need it for testing, introspection and analytics for your Cmds, etc. But if you're not leveraging it for those things then `Effect.fromCmd` is the simplest way to get up and running.

The `Effect` module must expose a `type Effect msg` and a `perform` function. These are the core of the module, and this pair defines which Effect's
can happen from your `init` and `update` on your frontend and how to perform them

> Note: Effects are unrelated to [the `BackendTask` API](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask). An `Effect` is something that is executed on the frontend of an `elm-pages` app.

## `Shared.elm`

This is where your site-wide layout goes. The `Shared.view` function receives the `view` from a
Route module, and can render it within a layout.

Must expose

- `Msg` - global `Msg`s across the whole app, like toggling a menu in the shared header view
- `Model` - shared state that persists between page navigations. This `Shared.Model` can be accessed by Route Modules.

## `Site.elm`

Defines global head tags and your manifest config.

Must expose

- `config : SiteConfig`

## `public`

Files in this folder are copied directly into `dist/` when you run `elm-pages build`. These files will also be served in the `elm-pages dev` server.

For example, if you had a file called `public/images/profile.jpg`, then you could access it at `http://localhost:1234/images/profile.jpg` in your dev server, or the corresponding path in your production domain.

## `index.ts`

This is the entrypoint for your JavaScript. Export an Object with a functions `load` and `flags`. Right now, this is the only place that user JavaScript code can be loaded. You can use `import` statements to load other JS files here.

`load` is an `async` function that will be called with a Promise that you can await to register ports on your Elm application (or just wait until the Elm application is loaded).

`flags` will be passed in to your `Flags` in your `Shared.elm` module.

```javascript
export default {
  load: async function (elmLoaded) {
    const app = await elmLoaded;
    // console.log("App loaded", app);
  },
  flags: function () {
    return "You can decode this in Shared.elm using Json.Decode.string!";
  },
};
```

## `style.css`

You can configure which CSS assets to load by customizing your `elm-pages.config.mjs` file.

This CSS file will be included on the page. It will also live reload if you make changes to this file.

Right now, this is the only user CSS file that is loaded. You can use CSS imports to load other CSS files here.

## `elm-pages.config.mjs`

- `vite` - The `elm-pages` config file is a JavaScript file that exports a config object. You can pass it a [Vite configuration](https://vitejs.dev/config/) to customize how `elm-pages` built-in Vite integration processes your assets in its dev server and build.
- `headTagsTemplate` - A function that returns a string of HTML that will be included in the `<head>` of every page. This is useful for including additional CSS or JS assets on the page. It is pre-processed by Vite.
- `preloadTagForFile` - Given a file name, return a boolen to indicate whether or not to include a preload tag for that asset.
- `adapter` - an adapter function to prepare your built application for deployment with a given framework or hosting provider. See the [full adapter docs page](/docs/adapters).
```js
import { defineConfig } from "vite";
import adapter from "elm-pages/adapter/netlify.js";

export default {
  adapter,
  vite: defineConfig({
    plugins: [
      /**/
    ],
  }),
  headTagsTemplate(context) {
    return `
<link rel="stylesheet" href="/style.css" />
<meta name="generator" content="elm-pages v${context.cliVersion}" />
`;
  },
  preloadTagForFile(file) {
    return !file.endsWith(".css");
  },
};
```

### elm-safe-virtual-dom Support

If you're using [elm-safe-virtual-dom](https://github.com/nicklydell/elm-safe-virtual-dom) to protect your app from browser extensions like Google Translate or Grammarly interfering with your DOM, static regions will work automatically. elm-pages detects elm-safe-virtual-dom in the compiled output and applies the appropriate patching strategy that works with its "tNode" tracking system.
