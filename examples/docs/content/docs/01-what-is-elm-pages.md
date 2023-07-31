# What is elm-pages?

`elm-pages` is a framework for building an Elm single-page app that is able to seamlessly interface with data from an Elm Backend. `elm-pages` is a hybrid framework, allowing you to define Routes that are either server-rendered
(for more dynamic content with user-specific or request-specific data) or pre-rendered at build-time (for generating static HTML files that are hosted through a CDN). You can mix and match server-rendered and pre-rendered routes in your app.

## The Backend

Elm Backend refers to a traditional server or serverless provider for [server-rendered routes](#server-rendered-routes), or your build environment for [pre-rendered routes](#pre-rendered-routes). Code that runs on the Elm Backend is co-located with the code for your Elm Frontend, allowing you to seamlessly reuse types and code. [The `elm-pages` Architecture](/docs/architecture) manages the glue to get the data from your Elm Backend to your Elm Frontend giving you a seamless experience of getting data back and forth between the server and the web page through the Route's `data` (as well as the `action` for server-rendered Routes).

## Route Modules

You [define Routes by adding Route Modules](/docs/file-based-routing) to the `app/Route/` folder. Each Route module has `Data`, which is a special type for data resolved with a [`BackendTask`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask). A Route's `Data` type has a lifecycle that is managed by the `elm-pages` framework (similar to how the Elm runtime manages the lifecycle your `Model` in a traditional Elm app), but it is resolved on your `elm-pages` Backend. The `Data` type is available to your `view` function, and it will be available without any loading spinners or Maybe values.

`elm-pages` is a superset of a vanilla Elm app, so the familiar Elm Architecture (`Model`/`init`/`update`/`view`) are all available in your Route modules in addition to your Route `Data` and other features that the `elm-pages` framework adds to the core Elm Architecture. `elm-pages` provides abstractions that leverage web standards to give a better user experience and a simpler developer experience. But because `elm-pages` is a superset of Elm, you can always perform vanilla `elm/http` requests from your Route modules or use other patterns you're familiar with from vanilla Elm apps.

## Server-Rendered Routes

Server-rendered routes in `elm-pages` give you a full-stack Elm application that lets you

- Resolve Elm data (through the [`BackendTask`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask) API) that is resolved server-side, and then available in your hydrated Elm application on the frontend
- Parse the incoming HTTP request and use it to get dynamic and/or user-specific data, including headers, cookies, and query parameters
- Set cookies and headers on the response, and manage signed key-value sessions using the [`Server.Session`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Server-Session) API
- Serve up an initial HTML response, including meta tags, from the server (helpful for both performance and SEO)
- Respond to follow-up form submissions using the [`Pages.Form`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Pages-Form) API

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

## Server-Rendered elm-pages Use Cases

`elm-pages` server-rendered routes are a good fit for applications with needs such as:

- Dynamic and/or user-specific content
- Login sessions
- Form submissions with client-side and server-side validations
- Responding to Form submissions
- Pending or Optimistic UI (showing in-flight form submissions)

Many of the core features of `elm-pages` are designed to support these use cases.

- [Forms](/docs/forms)
- In-flight submissions
- Server-side rendering
- [Session API](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Server-Session)
- [BackendTask API](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask)

Some examples of this include:

- Admin panels/CRUD applications
- eCommerce sites

## Pre-Rendered elm-pages Use Cases

In addition to server-rendered routes, `elm-pages` also supports pre-rendered routes. If you have a content-focused site with minimal user-specific data, then you can pre-render all of your pages to HTML at build-time (like this docs site you're reading now!).

Some of the benefits to pre-rendered routes include:

- Simpler hosting (you can use any static hosting provider)
- If your build is green, then your site is error-free.

Some examples of this include:

- Blogs
- Marketing sites
- Restaurant or other brochure sites
- Portfolios

## Deciding Between Server-Rendered and Pre-Rendered Routes

Consider a server-rendered route where you show some paid content if there is a logged in user with an active subscription, or a preview of the content with a call to action to sign up otherwise. This is a great use case for server-rendered routes. You will need to be more careful to handle your [`FatalError`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/BackendTask#FatalError) cases in your `BackendTask`s for that Route because you don't want the user to get a 500 error page. However, server-rendered routes give you the power to give a rich logged-in user experience with the ease of cookie-based sessions and the simplicity of data from a `BackendTask` that is available without any loading states to deal with (for the user or the developer). Imagine building that same route in a traditional Elm app. You would need to manage your user session using a JWT or similar client-side authentication technique, and your view would need to handle the intermediary states of authenticating, stale login session, or loading data from the backend. With a server-rendered route, since you have Elm code running on the server-side you can handle stale sessions with a server redirect response, and your loading states are resolved on the server-side before rendering.

If you are dealing with more static, public content, then pre-rendered routes come with some benefits. Consider a blog or documentation site. You don't need to be as careful with `FatalError`'s if you are using pre-rendered routes because you will have a chance to fix any errors that come up before the site goes live to your users (any `FatalError`'s your Routes resolve to will result in a build error). There is a tradeoff with flexibility, and there are reasons you may want to dynamically render content even if it seems relatively static. For example, you may want new articles, or edits, to go live immediately for a news site. If you pre-render your site, then you will need to build all of the your routes any time there is new or updated content. If you use server-rendered routes, this content would be live immediately since it is resolved on-demand at request-time.

## What's Not a Good Fit for elm-pages?

`elm-pages` is built around the architecture of serving Routes through an [Elm Backend](#the-backend) (either dynamic server or static build server). Some applications aren't a good fit for this kind of architecture at all. If the set of core features in [Server-Rendered Routes](#server-rendered-elm-pages-use-cases) and [Pre-Rendered Routes](#pre-rendered-elm-pages-use-cases) don't apply to your use case, then it may be possible to build your app with `elm-pages` but will likely feel like fitting a square peg in a round hole. So a good rule of thumb for deciding whether `elm-pages` is a good architecture for your application is considering whether you can benefit from communicating with an Elm Backend since this is the backbone of the featureset in `elm-pages`.

For example, if you're building an interactive game, the core experience of the application will likely be on a single route for most of the session. Serving the page with initial data from your Elm Backend in an `elm-pages` app would have neglible benefit, especially for loading the kinds of larger assets that are used in games. You would likely want to have a loading screen as part of the in-game experience, rather than a quick and slim set of initial data that can speed up the initial page load by resolving data on the server to minimize the latency. In this case, you may want to consider using a traditional Elm app with a client-side router. You can still use `elm-pages` for your settings pages, login, and landing pages. However, you will probably be able to define better abstractions for your game experience using traditional client-side rendered Elm app.

For similar reasons, an app like Figma isn't likely to be a good fit for `elm-pages`.

Some use cases like email client or productivity apps are a little fuzzier on this spectrum. Some of the core features in [Server-Rendered Routes](#server-rendered-elm-pages-use-cases) can be leveraged to build apps like email and calendar clients. You may decide that `elm-pages` is a good choice for your app for a similar use case. However, it's important to consider whether your app will benefit from the architecture of communicating with your [Elm Backend](#the-backend) when navigating to new routes, since this is a core part of the architecture that is baked into the `elm-pages` framework. `elm-pages` may add some functionality to support offline experiences in the future, but at the moment all page loads communicate with the Elm Backend to load page data. This offers a lot of benefits for performance and simplicity (as described in [Server Rendered Routes](#server-rendered-routes)), but the pros and cons of that architecture for these kinds of use cases are worth careful consideration.
