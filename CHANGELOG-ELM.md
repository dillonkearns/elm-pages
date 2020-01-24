# Changelog [![Elm package](https://img.shields.io/elm-package/v/dillonkearns/elm-pages.svg)](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/)

All notable changes to
[the `dillonkearns/elm-pages` elm package](http://package.elm-lang.org/packages/dillonkearns/elm-pages/latest)
will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.3] - 2020-01-23

### Fixed
- Fix missing content flash (that was partially fixed with [#48](https://github.com/dillonkearns/elm-pages/pull/48)) for
    some cases where paths weren't normalized correctly.

## [1.1.2] - 2020-01-20

### Fixed
- "Missing content" message no longer flashes between pre-rendered HTML and the Elm app hydrating and taking over the page. See [#48](https://github.com/dillonkearns/elm-pages/pull/48).

## [1.1.1] - 2020-01-04

### Fixed
* Don't reload pages when clicking a link to the exact same URL as current URL. Fixes [#29](https://github.com/dillonkearns/elm-pages/issues/29).

## [1.1.0] - 2020-01-03

Check out [this upgrade checklist](https://github.com/dillonkearns/elm-pages/blob/master/docs/upgrade-guide.md#upgrading-to-elm-package-110-and-npm-package-113) for more details and steps for upgrading your project.

### Added
- There's a new StaticHttp API. Read more about it in [this `StaticHttp` announcement blog post](http://elm-pages.com/blog/static-http)!
- The generated `Pages.elm` module now includes `builtAt : Time.Posix`. Make sure you have `elm/time` as a dependency in your project!
   You can use this when you make API requests to filter based on a date range starting with the current date.
   If you want a random seed that changes on each build (or every week, or every month, etc.), then you can use this time stamp
   (and perform modulo arithemtic based on the date for each week, month, etc.) and use that number as a random seed.

### Changed
- Instead of initializing an application using `Pages.application` from the generated `Pages` module, you now initialize the app
    using `Pages.Platform.application` which is part of the published Elm package. So now it's easier to browse the docs.
    You pass in some internal data from the generated `Pages.elm` module now by including
    this in the application config record:  `Pages.Platform.application { internals = Pages.internals, ... <other fields> }`.
- Add init argument and user Msg for initial PagePath and page changes (see [#4](https://github.com/dillonkearns/elm-pages/issues/4)).


## [1.0.1] - 2019-11-04

### Fixed
- Generate files for extensions other than `.md` and `.emu` (fixes [#16](https://github.com/dillonkearns/elm-pages/issues/16)).
   As always, be sure to also use the latest NPM package.
