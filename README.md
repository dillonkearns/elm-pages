# `elm-pages` [![Netlify Status](https://api.netlify.com/api/v1/badges/8ee4a674-4f37-4f16-b99e-607c0a02ee75/deploy-status)](https://app.netlify.com/sites/elm-pages/deploys) [![Build Status](https://github.com/dillonkearns/elm-pages/workflows/Elm%20CI/badge.svg)](https://github.com/dillonkearns/elm-pages/actions?query=branch%3Amaster) [![npm](https://img.shields.io/npm/v/elm-pages.svg)](https://npmjs.com/package/elm-pages) [![Elm package](https://img.shields.io/elm-package/v/dillonkearns/elm-pages.svg)](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/)

<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![All Contributors](https://img.shields.io/badge/all_contributors-5-orange.svg?style=flat-square)](#contributors-)
<!-- ALL-CONTRIBUTORS-BADGE:END -->

[![Deploy to Netlify](https://www.netlify.com/img/deploy/button.svg)](https://app.netlify.com/start/deploy?repository=https://github.com/dillonkearns/elm-pages-starter)

A **statically typed** site generator, written with pure Elm.

## Getting Started Resources

- [Quick start repo](https://github.com/dillonkearns/elm-pages-starter) [(live site hosted here)](https://elm-pages-starter.netlify.com)
- [Introducing `elm-pages` blog post](https://elm-pages.com/blog/introducing-elm-pages)
- [Quick Start page in docs site](https://elm-pages.com/docs)
- [`examples` folder](https://github.com/dillonkearns/elm-pages/blob/master/examples/) (includes https://elm-pages.com site source)

## Key features

### SEO made easy

With `elm-pages`, SEO is as easy
as calling a type-safe, high-level Elm API
and passing in data from your content's metadata.

The metadata is just Elm data that you define
however you want, using a Json Decoder to grab
data out of your markdown frontmatter.

```elm
import MyMetadata exposing (MyMetadata)

head : BlogMetadata -> List (Head.Tag Pages.PathKey)
head meta =
  Seo.summaryLarge
    { canonicalUrlOverride = Nothing
    , siteName = "elm-pages"
    , image =
      { url = PagesNew.images.icon
      , alt = meta.description
      , dimensions = Nothing
      , mimeType = Nothing
      }
    , description = meta.description
    , locale = Nothing
    , title = meta.title
    }
    |> Seo.article
      { tags = []
      , section = Nothing
      , publishedTime = Just (Date.toIsoString meta.published)
      , modifiedTime = Nothing
      , expirationTime = Nothing
      }
```

### Optimized for performance

`elm-pages` has a set of features built-in to make
sure your page is blazing fast on any device.

- Automatic page pre-rendering
- Page content is split up per-page so page content downloads and parses just-in-time
- Page pre-fetching on link hover

Try out `elm-pages`, open up Lighthouse, and
see for yourself! Or check out https://elm-pages.com
(find the source code in the [`examples/docs/`](https://github.com/dillonkearns/elm-pages/tree/master/examples/docs) folder).

## Built-in type-safety

`elm-pages` generates static Elm data for you
to make sure you don't have any broken links or images.
The SEO API even uses it to make sure you are only pointing to
valid images and pages so you have valid metadata!

For example, if you have a content folder like this:

```shell
- content
  - blog
    - index.md
    - hello-world.md
    - second-post.md
```

Then you will be able to access those pages in a
type-safe way like this from Elm:

```elm
-- this is a generated module
-- it is re-run whenever your `content` folder changes
-- just run `elm-pages develop` to start the watcher
import Pages exposing (pages)
import Pages.PagePath as PagePath exposing (PagePath)


indexPage : PagePath Pages.PathKey
indexPage =
  pages.blog.index


helloPostPage : PagePath Pages.PathKey
helloPostPage =
  pages.blog.helloWorld


secondPost : PagePath Pages.PathKey
secondPost =
  pages.blog.secondPost
```

## Offline Support

`elm-pages` uses pure elm configuration to setup
your progressive web app settings. This includes
a "source icon" which is used to generate your favicons
and icons for the images following best practices for
a progressive web app. The image is even a type-safe
`ImagePath` that guarantees you are using an available
image!

```elm
manifest : Manifest.Config Pages.PathKey
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

It will also take care of setting up a service worker
which will automatically cache the basic shell
for your application's compiled Elm code and
HTML container. The page content is currently cached
as it is loaded, but in the future there will
be an API to choose some pages to "warm up" in the cache.

## What's next?

Take a look at the current projects to see the current priorities!

https://github.com/dillonkearns/elm-pages/projects

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tr>
    <td align="center"><a href="https://github.com/danmarcab"><img src="https://avatars2.githubusercontent.com/u/1517969?v=4" width="100px;" alt=""/><br /><sub><b>Daniel Marín</b></sub></a><br /><a href="https://github.com/dillonkearns/elm-pages/commits?author=danmarcab" title="Code">💻</a></td>
    <td align="center"><a href="https://citric.id"><img src="https://avatars1.githubusercontent.com/u/296665?v=4" width="100px;" alt=""/><br /><sub><b>Steven Vandevelde</b></sub></a><br /><a href="https://github.com/dillonkearns/elm-pages/commits?author=icidasset" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/Y0hy0h"><img src="https://avatars0.githubusercontent.com/u/11377826?v=4" width="100px;" alt=""/><br /><sub><b>Johannes Maas</b></sub></a><br /><a href="#userTesting-Y0hy0h" title="User Testing">📓</a> <a href="https://github.com/dillonkearns/elm-pages/commits?author=Y0hy0h" title="Code">💻</a></td>
    <td align="center"><a href="https://github.com/vViktorPL"><img src="https://avatars1.githubusercontent.com/u/2961541?v=4" width="100px;" alt=""/><br /><sub><b>Wiktor Toporek</b></sub></a><br /><a href="https://github.com/dillonkearns/elm-pages/commits?author=vViktorPL" title="Code">💻</a></td>
    <td align="center"><a href="https://sunrisemovement.com"><img src="https://avatars1.githubusercontent.com/u/1508245?v=4" width="100px;" alt=""/><br /><sub><b>Luke Westby</b></sub></a><br /><a href="https://github.com/dillonkearns/elm-pages/commits?author=lukewestby" title="Code">💻</a></td>
  </tr>
</table>

<!-- markdownlint-enable -->
<!-- prettier-ignore-end -->
<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!
