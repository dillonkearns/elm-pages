---
{
  "type": "blog",
  "author": "Dillon Kearns",
  "title": "Introducing elm-pages 🚀 - elm's answer to Gatsby",
  "description": "Elm is the perfect fit for a static site generator. Learn about some of the features and philosophy behind elm-pages.",
  "published": "2019-09-21",
}
---

JAMstack frameworks, like [Gatsby](http://gatsbyjs.org), can make powerful optimizations because they are dealing with strong constraints (specifically, content that is known at build time). Elm is the perfect tool for the JAMstack because it can leverage those constraints and turn them into compiler guarantees. Not only can we do more with static guarantees using Elm, but we can get additional guarantees using Elm's type-system and managed side-effects. It's a virtuous cycle that enables a lot of innovation.

## Why use `elm-pages`?
That's a lot of abstract talk. But what does it actually look like to use `elm-pages`? What's in it for the users (both the end users, and the team using it to build their site)?

### Performance
- Pre-rendered pages for blazing fast first renders
- Lazy load page content for subsequent pages
- Your content is loaded as a single-page app behind the scenes, giving you smooth page changes
- Optimized image assets
- App skeleton is cached with a service worker (with zero configuration) so it's available offline

One of the early beta sites that used `elm-pages` instantly shaved off over a megabyte for the images on a single page! Optimizations like that need to be built-in and automatic otherwise some things inevitably slip through the cracks.

### Type-safety and simplicity

- The type system guarantees that you use valid images and routes in the right places
- You can even set up a validation to give build errors if there are any broken links or images in your markdown
- You can set up validations to define your own custom rules for your domain! (Maximum title length, tag name from a set to avoid multiple tags with different wording, etc.)

## Progressive Web Apps

[Lighthouse recommends having a Web Manifest file](https://developers.google.com/web/tools/lighthouse/audits/manifest-exists) for your app to allow users to install the app to your home screen and have an appropriate icon, app name, etc.
Elm pages gives you a type-safe way to define a web manifest for your app:

```elm
manifest : Manifest.Config PagesNew.PathKey
manifest =
    { backgroundColor = Just Color.white
    , categories = [ Pages.Manifest.Category.education ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "elm-pages - A statically typed site generator."
    , iarcRatingId = Nothing
    , name = "elm-pages docs"
    , themeColor = Just Color.white
    , startUrl = pages.index
    , shortName = Just "elm-pages"
    , sourceIcon = images.icon
    }
```

Lighthouse will also ding you [if you don't have the appropriately sized icons and favicon images](https://developers.google.com/web/tools/lighthouse/audits/manifest-contains-192px-icon). `elm-pages` guarantees that you will follow these best practices (and gives you the confidence that you haven't made any mistakes). It will automatically generate the recommended set of icons and favicons for you, based on a single source image. And, of course, you get a compile-time guarantee that you are using an image that exists!

```haskell
sourceIcon = images.doesNotExist
```

Results in this elm compiler error:
![Missing image compiler error](/images/compiler-error.png)

## `elm-pages` is just Elm!
`elm-pages` hydrates into a full-fledged Elm app (the pre-rendered pages are just for faster loads and better SEO). So you can do whatever you need to using Elm and the typed data that `elm-pages` provides you with.

## SEO
One of the main motivations for building `elm-pages` was to make SEO easier and less error-prone. Have you ever seen a link shared on Twitter or elsewhere online that just renders like a plain link? No image, no title, no description. As I user, I'm a little afraid to click those links because I don't have any clues about where it will take me. As a user posting those links, it's very anticlimactic to share the blog post that I lovingly wrote only to see a boring link there in my tweet sharing it with the world.


In a future post, I'll talk about how `elm-pages` makes SEO dead simple. For now, you can take a look at [the built-in `elm-pages` SEO module](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/Head-Seo).

