## Why does elm-pages use Lamdera? Is it free?

Starting with elm-pages v3, the Lamdera compiler is used instead of the Elm compiler. This is completely independent of the
Lamdera hosted service. The Lamdera compiler is completely free to use and will not have any costs now or in the future.

The reason elm-pages v3 began using the Lamdera compiler is for its automatic serialization of Elm data, which is known
as Lamdera Wire. The Lamdera compiler is a fork of the Elm compiler which adds some functionality including Lamdera Wire. The
elm-pages framework uses this under the hood. The BackendTask `data` you define in your elm-pages Route Modules is resolved either at
build-time (for pre-rendered routes, resolved when you run `elm-pages build`), or at request-time (for server-rendered routes). Imagine you
have sensitive data that can't be exposed in your client-side app, like an API key to access data. Since BackendTask's are resolved at build-time
or request-time (they are NOT resolved on the client-side in the browser), you can safely use these secrets.

The secrets you use to resolve that data won't end up on the client-side at all unless you include any sensitive data in your Route Module's `Data` value.
The automatic serialization we get from the Lamdera Compiler gives us this abstraction for free. Before elm-pages v3, the `OptimizedDecoder` abstraction
was used to serialize all data involved in resolve the BackendTask. This would include any secret environment variables that were used along the way, which
is why elm-pages v2 had the Secrets API - to ensure that you could use sensitive values without them showing up on the client-side. Thanks to the Lamdera Compiler,
we're able to serialize only the final value for your Route Module's `Data` (not any of the intermediary values), so the user can reason about it more easily
and write less code. It also improves performance because we serialize the `Data` value in a binary format, reducing the transfer size.

The Lamdera Compiler is free to use, but is currently only source-available to enterprise customers of the hosted Lamdera service.
In the future, it's possible that the Lamdera Wire functionality will be made available in
an open source, source-available tool, but there's no guarantee of that or timeline.

## Is elm-pages full-stack? Can I use it for pure static sites without a server? Can I use it for server-rendered pages with dynamic user content?

Starting with `elm-pages` v3, the answer to all of the above is yes! Before `elm-pages` v3, it was a static-only site generator, meaning that you run
a build step (`elm-pages build`), it outputs files, and a static host (like Netlify or GitHub pages) serves up those static files. In elm-pages v3,
if you only use `RouteBuilder.preRender`, then you can use elm-pages as a purely static site generator and host your site without any dynamic server rendering
or related server hosting functionality (just serve the generated files from `elm-pages build` like before).

But starting with v3, you are also able to define server-rendered routes using `RouteBuilder.serverRender`. With this lifecycle, you're able to respond dynamically
to a request, which means that you can do things like

- Check for a session cookie
- If the session cookie is present, use a BackendTask to lookup the user using an API call and server-render a page with user-specific page content
- If the session cookie is absent, redirect to the login page using an HTTP 301 response code
- Load data dynmically at request-time, so every time the page is loaded you have the latest data (compared to statically built sites that have data from the time when the site was last built)

## Can you pass flags in to your `elm-pages` app?

Yes, see the [Pages.Flags module](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Pages-Flags). Note that elm-pages apps have a different life-cycle than standard Elm applications because they pre-render pages (either at build-time for static routes, or at request-time for server-rendered routes). So for example, if you get the window dimensions from the flags and do responsive design based on that, then you'll see a flash after the client-side code takes over since you need to give a value to use at pre-render time (before the app has reached the user's browser so before there are any dimensions available). So that semantics of the flags are not quite intuitive there.So you have to explicitly say how to handle the case where you don't have access to flags.

You can see more discussion here for background into the design: https://github.com/dillonkearns/elm-pages/issues/9.

## How do you handle responsive layouts when you don't know the browser dimensions at build time?

A lot of users are building their `elm-pages` views with `elm-ui`, so this is a common question because
`elm-ui` is designed to do responsive layouts by storing the browser dimensions in the Model and
doing conditionals based on that state.

With `elm-pages`, and static sites in general, we are building pre-rendered HTML so we can serve it up
really quickly through a CDN, rather than serving it up with a traditional server framework. That means
that to have responsive pages that don't have a page flash, we need to use media queries to make our pages responsive.
That way, the view is the same no matter what the dimensions are, so it will pre-render and look right on whatever
device the user is on because the media queries will take care of making it responsive.

Since `elm-ui` isn't currently built with media queries in mind, it isn't a first-class experience to use them with
`elm-ui`. One workaround you can use is to define some responsive classes that simply show or hide an element based on
a media query, and apply those classes. For example, you could show the mobile or desktop version of the navbar
by having a `mobile-responsive` and `desktop-responsive` class and rendering one element with each respsective class.
But the media query will only show one at a time based on the dimensions.

## Can you define routes based on external data like a CMS or API response?

Yes, with elm-pages 2.0 and later you can! For pre-rendered routes, you pass in a BackendTask to pull in a list of pages to render for that route.
For server-rendered routes, you can choose to render a 404 page (or other error page) for routes you don't want to respond to. You can use both the
RouteParams and a BackendTask to decide whether you want to give a 404 or render the page with your resolved Data.
