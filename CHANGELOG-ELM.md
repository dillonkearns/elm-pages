# Changelog [![Elm package](https://img.shields.io/elm-package/v/dillonkearns/elm-pages.svg)](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/)

All notable changes to
[the `dillonkearns/elm-pages` elm package](http://package.elm-lang.org/packages/dillonkearns/elm-pages/latest)
will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- The generated `Pages.elm` module now includes `builtAt : Time.Posix`. Make sure you have `elm/time` as a dependency in your project!
   You can use this when you make API requests to filter based on a date range starting with the current date.
   If you want a random seed that changes on each build (or every week, or every month, etc.), then you can use this time stamp
   (and perform modulo arithemtic based on the date for each week, month, etc.) and use that number as a random seed.

### Changed
- Instead of initializing an application using `Pages.application` from the generated `Pages` module, you now initialize the app
    using `Pages.Platform.application` which is part of the published Elm package. So now it's easier to browse the docs.
    You pass in some internal data from the generated `Pages.elm` module now by including
    this in the application config record:  `Pages.Platform.application { internals = Pages.internals, ... <other fields> }`.