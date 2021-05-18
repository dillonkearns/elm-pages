# What is elm-pages

`elm-pages` is a framework for building an Elm single-page app with pre-rendered HTML pages.

It has a built-in file-based router, and a `DataSource` API to help you bring in typed Elm data that's baked in to the page (no loading spinners).

Some of the core features include

- Pre-render routes to HTML
- Hydrate to a full Elm app, with client-side navigation after initial load
- File-based routing
- `DataSource`s allow you to pull HTTP or file data to a given page and have it available before load
- Dev server with hot reloading (including when you modify a file that is used as a `DataSource`)
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
