# What is elm-pages?

`elm-pages` is a framework for building an Elm single-page app that is able to seamlessly interface with data from an Elm Backend. `elm-pages` is a hybrid framework, allowing you to define Routes that are either server-rendered
(for more dynamic content with user-specific or request-specific data) or pre-rendered at build-time (for generating static HTML files that are hosted through a CDN). You can mix and match server-rendered and pre-rendered routes in your app.

## The Backend

Elm Backend refers to a traditional server or serverless provider for [server-rendered routes](#server-rendered-routes), or your build environment for [pre-rendered routes](#pre-rendered-routes). Code that runs on the Elm Backend is co-located with the code for your Elm Frontend, allowing you to seamlessly reuse types and code. [The `elm-pages` Architecture](/docs/architecture) manages the glue to get the data from your Elm Backend to your Elm Frontend giving you a seamless experience of getting data back and forth between the server and the web page through the Route's `data` (as well as the `action` for server-rendered Routes).

## Route Modules

You [define Routes by adding Route Modules](/docs/file-based-routing) to the `app/Route/` folder. Each Route module has `Data`, which is a special type for data resolved with a [`BackendTask`](https://package.elm-lang.org/packages/dillonkearns/elm-pages-v3-beta/latest/BackendTask). A Route's `Data` type has a lifecycle that is manged by the `elm-pages` framework (similar to how the Elm runtime manages the lifecycle your `Model` in a traditional Elm app), but it is resolved on your `elm-pages` Backend. The `Data` type is available to your `view` function, and it will be available without any loading spinners or Maybe values.

`elm-pages` is a superset of a vanilla Elm app, so the familiar Elm Architecture (`Model`/`init`/`update`/`view`) are all available in your Route modules in addition to your Route `Data` and other features that the `elm-pages` framework adds to the core Elm Architecture. `elm-pages` provides abstractions that leverage web standards to give a better user experience and a simpler developer experience. But because `elm-pages` is a superset of Elm, you can always perform vanilla `elm/http` requests from your Route modules or use other patterns you're familiar with from vanilla Elm apps.

## Server-Rendered Routes

Server-rendered routes in `elm-pages` give you a full-stack Elm application that lets you

- Resolve Elm data (through the [`BackendTask`](https://package.elm-lang.org/packages/dillonkearns/elm-pages-v3-beta/latest/BackendTask) API) that is resolved server-side, and then available in your hydrated Elm application on the frontend
- Parse the incoming HTTP request and use it to get dynamic and/or user-specific data, including headers, cookies, and query parameters
- Set cookies and headers on the response, and manage signed key-value sessions using the [`Server.Session`](https://package.elm-lang.org/packages/dillonkearns/elm-pages-v3-beta/latest/Server-Session) API
- Serve up an initial HTML response, including meta tags, from the server (helpful for both performance and SEO)
- Respond to follow-up form submissions using the [`Pages.Form`](https://package.elm-lang.org/packages/dillonkearns/elm-pages-v3-beta/latest/Pages-Form) API

The goals of server-rendered routes in `elm-pages` are to support performance and maintainability.

- **Performance** - By resolving data on the server, you can avoid extra round trips to communicate with your backend. In order to get these benefits, it is important that your application architecture hosts your elm-pages application in the same data center as your backend.
- **Maintainability** - By using the same Elm code on the server and the client, you can remove a layer of glue code and remove some intermediary states and types.

## Pre-Rendered Routes

If you prefer to use a static hosting provider, or if you have a content-focused site with minimal user-specific data, then you can pre-render all of your pages to HTML at build-time (like this docs site you're reading now!).

It has a built-in file-based router, and a [`BackendTask`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask) API to help you bring in typed Elm data that's baked in to the page (no loading spinners).

Some of the core features include

- Pre-render routes to HTML
- Hydrate to a full Elm app, with client-side navigation after initial load
- File-based routing
- `BackendTask`s allow you to pull HTTP or file data to a given page and have it available before load
- Dev server with hot reloading (including when you modify a file that is used as a `BackendTask`)
- A nice type-safe API for SEO
- Generate files, like RSS, sitemaps, podcast feeds, or any other strings you can output with pure Elm

## When should I use elm-pages?

`elm-pages` is designed to help you build a site with great SEO. It's a really good fit for sites that are based on content, such as:

- eCommerce
- Blogs
- Marketing sites
- Restaurant or other brochure sites
- Portfolios

It might not be the right choice for mostly dynamic apps. If you want file-based routing for a mostly dynamic Elm single-page app, the [`elm-spa`](https://elm-spa.dev/) framework could be a good fit.

Why not just use `elm-pages` in these cases? You can evaluate the tradeoffs for your particular use case, but here are some baked-in opinions that may help evaluate whether `elm-pages` is a good fit.

- `elm-pages build` will pre-render the HTML for all of your routes. If you want to handle routes with client-side rendering only, that's not currently an option in elm-pages, and if you don't have a need for the pre-rendered HTML in your app, then it's better to avoid that. With `elm-pages`, the HTML for each page will either be pre-rendered at the build step, or server-rendered on each request.
- On single-page app page navigations, `elm-pages` will always request the `Data` for the page it's going to. It tries to optimize it as much as possible by letting you prefetch the data when you hover over a link. That usually gives you about ~150ms or so to load it before the user clicks a link, which is actually enough to make it feel mostly instant. This enables some of the key features in `elm-pages`, but if you're not using those features then it's not providing any value

If your use case does benefit from pre-rendered HTML and `BackendTask`s, `elm-pages` gives you a lot of features out of the box that aim to make that a smooth experience for users and developers.
