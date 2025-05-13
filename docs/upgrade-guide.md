# `elm-pages` Upgrade Guide

## Upgrading to Elm Package 1.1.0 and NPM Package 1.1.3

Here's a diff to help guide you through the change: https://github.com/dillonkearns/elm-pages-starter/commit/5de5102d706f4a360df94e5493ceff27ebd61587.

### High level changes

- A few modules that were previously copied to the `gen` folder are now part of the published package.
  This makes it easier to discover the functionality through the package site and understand
  how to initialize an `elm-pages` app.
- The new `StaticHttp` API now allows you to make HTTP requests during the build step that are built
  into your app's assets (see the [StaticHttp announcement blog post](http://elm-pages.com/blog/static-http)).
  If you don't have any StaticHttp data for a given page, you can use `StaticHttp.succeed` (see the
  [changes to the view function in the elm-pages-starter diff](https://github.com/dillonkearns/elm-pages-starter/commit/5de5102d706f4a360df94e5493ceff27ebd61587#diff-de84bd170bc37fbce0a7076c0125dd29L110-R142)).

### Step by step upgrade checklist

- Be sure to install the latest NPM package _and_ the latest elm package (NPM version 1.1.3 and Elm package version 1.1.0 at
  the time of this writing).
- `elm install elm/time` (the generated `Pages.elm` has a new `builtAt` value of
  type `Time` so this needs to be installed for it to compile).
- The `init` function now takes an additional argument, the page you're on when you load the app.
  You can just add a discarded argument [like this](https://github.com/dillonkearns/elm-pages-starter/commit/5de5102d706f4a360df94e5493ceff27ebd61587#diff-de84bd170bc37fbce0a7076c0125dd29R60).
- The `head` function is [no longer called from `Pages.application`](https://github.com/dillonkearns/elm-pages-starter/commit/5de5102d706f4a360df94e5493ceff27ebd61587#diff-de84bd170bc37fbce0a7076c0125dd29L64) because it now has access to
  StaticHttp data. Instead, it is part of the `view` function, see [this diff](https://github.com/dillonkearns/elm-pages-starter/commit/5de5102d706f4a360df94e5493ceff27ebd61587#diff-de84bd170bc37fbce0a7076c0125dd29R141).
