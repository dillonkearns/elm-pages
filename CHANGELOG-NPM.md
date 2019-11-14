# Changelog [![npm](https://img.shields.io/npm/v/elm-pages.svg)](https://npmjs.com/package/elm-pages)

All notable changes to
[the `elm-pages` npm package](https://www.npmjs.com/package/elm-pages)
will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
