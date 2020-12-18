## Can you pass flags in to your `elm-pages` app?
I'm trying to figure out the most intuitive way to model the concept of flags in `elm-pages`. Because the value of flags will be different during Pre-Rendering and Client-Side Rendering, just passing a single flag value would be misleading and make it seem like you have access to JS in the context of the user's browser on init. But you have to account for the Pre-Rendering phase as well, so flags has two different meanings.

So for example, if you get the window dimensions from the flags and do responsive design based on that, then you'll see a flash after the client-side code takes over since it will run with a different value for flags. So that semantics of the flags are not quite intuitive there. You can achieve the same thing with a port, but the semantics are a little more obvious there because you now have to explicitly say how to handle the case where you don't have access to flags.

The discussion is being tracked here: https://github.com/dillonkearns/elm-pages/issues/9.

I think the likely solution here will be to pass in flags, but wrap it in a custom type that makes the current lifecycle stage more clear:

```elm
type Flags value =
  FromPrerenderer value | FromUsersBrowser value
```

Right now, you can achieve the same result with a port.

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

You can't do that at the moment. Keep an eye on issue [#76](https://github.com/dillonkearns/elm-pages/issues/76), which is tracking that feature. It's a high priority, but involves some significant work under the hood.

Currently, the only way to add new routes with `elm-pages` is by adding files to the `content/` folder. The routes in your `elm-pages` app are a direct mapping of the file paths in the `content/` folder.

In the meantime, there are two workarounds:

1. Use a git-based CMS. For example, https://forestry.io/ and https://www.netlifycms.org/ are both git-based. This means that adding new content to the CMS makes a pull request and adds that content to your repo. This works out of the box with elm-pages, because it will just add files to your `content/` folder. See https://github.com/dillonkearns/elm-pages-netlify-cms-starter.

2. Alternatively, you can create a simple script (with NodeJS or bash) that runs before you do your `elm-pages build` or `elm-pages develop` command. That allows you to make any API requests you need to figure out the routes of your app. Then you'll need to write files to the `content/` folder based on that response. You can include some frontmatter (between the `---`'s at the top of the files you output) with some JSON data at the top. Then you can decode this data as metadata, and use it to perform StaticHttp requests for that page.

