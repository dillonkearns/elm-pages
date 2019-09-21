---
{
  "type": "blog",
  "author": "Dillon Kearns",
  "title": "Introducing elm-pages - elm's answer to Gatsby",
  "description": "TODO",
  "published": "2019-09-20",
}
---

JAM Stack frameworks, like Gatsby, can make powerful optimizations because they are dealing with strong constraints (specifically, content that is known at build time). Elm is the perfect tool for the JAM Stack because it can leverage those constraints and turn them into compiler guarantees. Not only can we do more with the guarantees we're given using Elm, but we can leverage Elm's type-system and purity to provide even more constraints, allowing for better optimizations and stronger guarantees.

## Why should I care?

What do these optimizations and strong guarantees mean for developers and users? Let's dive into some of these features, and why the matter.

### Performance

- Pre-rendered pages
- Lazily load content for subsequent pages
- Optimize image assets
- App skeleton is cached with a service worker (with zero configuration) so it's available offline
- Developers can configure caching strategies for images and content with a type-safe pure Elm interface

### Type-safety and simplicity

- The type system guarantees that you use valid images and routes in the right places
- You can even set up a validation to give build errors if there are any broken links or images in your markdown
- You can use the same API to define your own custom validations for your domain!

* Accessibility

Why another JAM Stack framework?

And more interestingly, why in Elm? Well, it turns out Elm is actually a perfect tool for building JAM Stack apps.

But first, let me give a brief intro to JAM Stack in case you're not familiar. You may be familiar with static site generators from many years ago, like Jekyll. These were great for building personal blogs and other lightweight sites.

But if you want to build a production application, and something for a company, you'll want to do more. You need to pull in external data, perhaps you have content that a content editor works on (and you don't want them to write markdown directly in your git repo). JAMStack is great for this type of application because it allows you to build a highly performant app. For example, if you have an eCommerce site, there is a lot of research showing that performance has a very direct impact on conversion rates and user engagement. So you want to use a nice modern frontend framework, but you also need it to having blazing fast load times. The answer is JAM Stack.

## Why Elm is the perfect fit for JAM Stack

The reason JAM Stack applications are able to make so many optimizations so easily and effectively is because of the static nature of the content. You may be drawing it in from an external data source, but it all happens at a single pinch point in the build step. Once you grab the data, you know exactly what you're dealing with. So you can make all sorts of optimizations in the build step, leaving the client-side application with minimal heavy-lifting. And yet, you can do whatever rich dynamic functionality you want because it's just a regular modern frontend application once it reaches the client's browser.

So JAM Stack apps are all about taking advantage of its knowledge of your static content. Well, Elm's strengths are very similar. It is a statically typed language. And unlike JavaScript, TypeScript, ReasonML, etc., Elm is a _static_ language. That means you can't have a function, or a variable, etc. that didn't exist at compile time, and then suddenly comes into existence. Elm knows everything about your app at compile-time. That means that as a developer, you get all sorts of great guarantees and it leads to a really great developer experience, and very bug-free and reliable user experience.

`elm-pages` takes advantage of these characteristics of the elm language. It is a static framework... So for example, elm-pages knows what image assets and what routes you have in your app. And this data is available at compile-time.

So if you want to link to an image asset, or link to a page in your app, from within your elm code, you can get your editor's autocompletion, and if you make a typo or refer to a removed image or route, you'll get a nice friendly elm error message.

TODO - short gif showing using editor autocompletion filling in a route, and showing what happens if you have a typo or remove an image.

You can even leverage this functionality from within markdown or elm-markup so you get errors (and the build will fail) if you have any broken links or images in your markup content.

elm-pages gives you a cohesive, simple experience. It builds a performant single-page app for you, with server-side pre-rendered pages.

## Progressive Web Apps

[Lighthouse recommends having a Web Manifest file](https://developers.google.com/web/tools/lighthouse/audits/manifest-exists) for your app to allow users to install the app to your home screen and have an appropriate icon, app name, etc.
Elm pages gives you a type-safe way to define a web manifest for your app.

```haskell
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
