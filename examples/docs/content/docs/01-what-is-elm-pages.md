# What is elm-pages?

`elm-pages` is a framework for building an Elm single-page app with pre-rendered HTML pages.

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
