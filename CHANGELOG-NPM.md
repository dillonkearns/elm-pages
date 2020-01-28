# Changelog [![npm](https://img.shields.io/npm/v/elm-pages.svg)](https://npmjs.com/package/elm-pages)

All notable changes to
[the `elm-pages` npm package](https://www.npmjs.com/package/elm-pages)
will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.2] - 2020-01-27

### Fixed
- Dev server only terminates with unrecoverable build errors, and now will
     continue running with recoverable errors like metadata parsing errors.
     See [#58](https://github.com/dillonkearns/elm-pages/pull/58).

### Added
- The `pagesInit` function that wraps the way you initialize your app in `index.js` now returns a Promise
    so you can wire up ports to it once it's initialized. See [#50](https://github.com/dillonkearns/elm-pages/pull/50).
    Thank you [@icidasset](https://github.com/icidasset)! 🙏

## [1.2.1] - 2020-01-20

### Fixed
- Removed a couple of debug console.log statements from the CLI.

## [1.2.0] - 2020-01-20

### Changed
- Changed the CLI generator to expect code from the new Elm package from the new
    `generateFiles` hook in `Pages.Platform.application`.

## [1.1.8] - 2020-01-20

### Fixed
- "Missing content" message no longer flashes between pre-rendered HTML and the Elm app hydrating and taking over the page. See [#48](https://github.com/dillonkearns/elm-pages/pull/48).

## [1.1.7] - 2020-01-12

### Fixed
- Newlines and escaped double quotes (`"`s) are handled properly in content frontmatter now. See [#41](https://github.com/dillonkearns/elm-pages/pull/41). Thank you [Luke](https://github.com/lukewestby)! 🎉🙏

## [1.1.6] - 2020-01-04

### Added
- Added hot reloading for code changes! That means that in dev mode (`elm-pages develop`),
    you can change your code and the changes will be reloaded in your browser for you instantly.
    Note that changing files in your `content` folder won't yet be instantly reloaded, that will
    be a future task. See [#35](https://github.com/dillonkearns/elm-pages/pull/35).

## [1.1.5] - 2020-01-03

### Fixed
- Fixed the bug that showed blank pages and failed page reloads when you change files in the `content` folder. Thank you so much [@danmarcab](https://github.com/danmarcab) for contributing the fix! See [#23](https://github.com/dillonkearns/elm-pages/pull/23).

## [1.1.4] - 2020-01-03

### Changed
- Updated `favicons-webpack-plugin` to latest version. Had to upgrade to `html-webpack-plugin@4.0.0-beta.11`
  for this. See [#32](https://github.com/dillonkearns/elm-pages/issues/32).

## [1.1.3] - 2020-01-03

*Check out [this upgrade checklist](https://github.com/dillonkearns/elm-pages/blob/master/docs/upgrade-guide.md#upgrading-to-elm-package-110-and-npm-package-113) for more details and steps for upgrading your project.

### Changed
- Added `StaticHttp` requests in the CLI process (see the Elm package changelog).

## [1.0.41] - 2019-11-14

### Fixed
- Fixed a regression where elm-markup frontmatter was being incorrectly parsed as JSON
    (fixes [#20](https://github.com/dillonkearns/elm-pages/issues/20)).

## [1.0.40] - 2019-11-04

### Fixed
- Generate files for extensions other than `.md` and `.emu` (fixes [#16](https://github.com/dillonkearns/elm-pages/issues/16)).
   As always, be sure to also use the latest Elm package.

### Added
- Ability to use a custom port for dev server ([#10](https://github.com/dillonkearns/elm-pages/pull/10); thank you [@leojpod](https://github.com/leojpod)! 🎉)

## [1.0.39] - 2019-10-18

### Fixed
- Use hidden `<div>` to listen for Elm view renders instead of wrapping entire
   page in an extra div. Fixes [#5](https://github.com/dillonkearns/elm-pages/issues/5).

### Changed
- Add `onPageChange : PagePath Pages.PathKey -> userMsg` field to `Pages.application` config record.
    This is analagous to `onUrlChange` in `Browser.application`, except that you get a
    type-safe `PagePath Pages.PathKey` because it is guaranteed that you will only
    go to one of your static routes when this `Msg` is fired. Fixes [#4](https://github.com/dillonkearns/elm-pages/issues/4).
