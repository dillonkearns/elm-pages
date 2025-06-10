# Changelog [![Elm package](https://img.shields.io/elm-package/v/dillonkearns/elm-pages.svg)](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/)

All notable changes to
[the `dillonkearns/elm-pages` elm package](http://package.elm-lang.org/packages/dillonkearns/elm-pages/latest)
will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [10.2.2] - 2025-06-10

### Fixed

- Fixed issue where `url : Maybe PageUrl` was always `Nothing` in view function. See [#490](https://github.com/dillonkearns/elm-pages/issues/490).


## [10.2.1] - 2025-03-05

### Fixed

- Apply Simon's HTML escaping fixes to avoid HTML injection vector in cases where HTML tag names or attributes were coming from user-controlled values. See [#524](https://github.com/dillonkearns/elm-pages/pull/524).

## [10.2.0] - 2024-12-12

### Changed

- Updated version constraint so users now need to use "mdgriffith/elm-codegen": "5.0.0 <= v < 6.0.0" (be sure to update your `scripts/elm.json` as well!)

### Fixed

- Fixed an issue in Form.withOnSubmit where it wasn't wired through in the platform code.

## [10.1.0] - 2024-04-28

### Added

- `BackendTask.Stream` API for creating and running/reading a pipeline of streams through NodeJS's native Stream APIs, including executing shell commands.
- `Pages.Script.command` and `Pages.Script.exec` functions for running shell commands (simpler verison of the command helpers in `BackendTask.Stream`, which allow piping input to/from the commands, and piping multiple commands together).
- `BackendTask.Glob.captureStats` for capturing `FileStats` for `Glob` matches. Can be used to capture file metadata including size, created time, last modified time, etc.
- `BackendTask.Glob.fromString` and `BackendTask.Glob.fromStringWithOptions` allow capturing matching file paths directly from a string pattern. Useful for use with executing shell commands since there is no glob expansion in the command API.
- `Pages.Script.Spinner` module for executing `BackendTask`s with loading spinners in `elm-pages` scripts.
- `BackendTask.Do` module with helpers for using continuation-style in scripts or `BackendTask` definitions.
- `BackendTask` now carries context that effects verbosity (`quiet`), working directory (`inDir`), and environment variables (`withEnv`).
- New functions in `BackendTask` module: `do`, `doEach`, `failIf`, `sequence`
- New functions in `Pages.Script` module: `doThen`, `question`, `sleep`, `which`, `expectWhich`.

## Fixed

- Redirecting to an external URL from an `action` now redirects correctly.
- Fixed error when Glob pattern had leading `./` (see [#469](https://github.com/dillonkearns/elm-pages/pull/469))
- Fixed `FilesAndFolders` option in `Glob` module, (see [#461](https://github.com/dillonkearns/elm-pages/pull/461))

## [10.0.3] - 2024-01-10

### Fixed

- Update elm-review version for an internally used rule to the latest Elm package to support newer elm-review NPM executable (fixes [#364](https://github.com/dillonkearns/elm-pages/issues/364)).
- Allow reading files with absolute paths (still reads relative path by default), see [#390](https://github.com/dillonkearns/elm-pages/issues/390).
- Fix `Scaffold.Route.preRender` - added an incorrect parameter that resulted in a compilation error in generated boilerplate.

### Changed

- Change `Scaffold.Route.preRender` to intelligently use `RouteBuilder.single` or `RouteBuilder.preRender` as appropriate
  based on whether the `moduleName` to generate has any dynamic route segments in it. `Scaffold.Route.single` is therefore deprecated as obsolete and will be removed in a future release.
- Updated version constraint so users now need to use "mdgriffith/elm-codegen": "4.0.0 <= v < 5.0.0" (be sure to update your `scripts/elm.json` as well!)
- Updated version constraint so users now need to use "dillonkearns/elm-bcp47-language-tag": "2.0.0 <= v < 3.0.0"

## [10.0.2] - 2023-09-07

### Fixed

- Cleaned up handling of navigating to new pages with query parameters, and navigating to links with `#`'s (named anchors). See [#389](https://github.com/dillonkearns/elm-pages/issues/389).
  Thank you to [`@kyasu1`](https://github.com/kyasu1) for the issue report and suggested fixes!

## [8.0.2] - 2021-08-03

### Fixed

- Change htmlFor HTML property to for HTML attribute in rendered HTML.

## [8.0.1] - 2021-08-01

### Fixed

- `<style>` tags were escaping `>` characters when they should be preserved in that context. Fixed the pre-rendered HTML escaping to not escape for style tags.

### Changed

- Removed an argument from Site.config.

## [8.0.0] - 2021-07-31

### Added

- You can now set the language of the root document with `Head.rootLanguage`.

### Changed

- Replaced `Pages.PagePath.PagePath pathKey` type with `Path`. The latest `elm-pages` generates a `Route` type for you, so you get
  some type-safety from that already. In a future release, there will likely be a tool to help integrate DataSource values with `elm-review`
  so you can check that programatically referenced pages exist (not just the route but the specific page).
- `Pages.Platform.init` is no longer used to create the main entrypoint. Instead, `elm-pages` wires that up under the hood from the main files you write.
- `StaticHttp` has been renamed to `DataSource.Http`. The core `DataSource` module has the `DataSource` type and the functions `map`, `andThen`,and other functions that aren't HTTP specific. There are additional modules now `DataSource.Glob`, `DataSource.Port`, and `DataSource.File`.

### Removed

- `Pages.ImagePath.ImagePath pathKey` has been removed - an `elm-review` integration could help users build checks for referencing valid files in the future,
  but in a way that doesn't increase the bundle size (generating a record with entries for every page and every image file increases the Elm bundle size as the number of
  pages/files grows, whereas using `elm-review` doesn't incur a runtime cost at all).

## [7.0.0] - 2020-10-26

See the upgrade guide for some information for getting to the latest version, and how to try out the 2 new opt-in beta features: https://github.com/dillonkearns/elm-pages/blob/master/docs/7.0.0-elm-package-upgrade-guide.md.

### Fixed

- Fixed a bug where using `ImagePath.external` in any `Head` tags would prepend the canonical site URL to the external URL, creating an invalid URL. Now it will only prepend the canonical site URL for local images, and it will use external image URLs directly with no modifications.
- StaticHttp performance improvements - whether you use the new beta build or the existing `elm-pages build` or `elm-pages develop` commands, you should see significantly faster StaticHttp any place you combined multiple StaticHttp results together. I would welcome getting any before/after performance numbers!

### Changed

- There is now an `icons` field in the `Manifest.Config` type. You can use an empty List if you are not using the beta no-webpack build (it will be ignored if you use `elm-pages build`, but will be used going forward with the beta which will eventually replace `elm-pages build`).

### Added

- There are 2 new beta features, a new beta no-webpack build and a beta Template Modules feature (see https://github.com/dillonkearns/elm-pages/blob/master/docs/7.0.0-elm-package-upgrade-guide.md for detailed info and instructions).

## [6.0.0] - 2020-07-14

### Fixed

- Fixed missing content message flash for pages that are hosted on a sub path: https://github.com/dillonkearns/elm-pages/issues/106.

## [5.0.2] - 2020-06-16

### Fixed

- Fixed issue where CLI would hang when fetching StaticHttp data for `generateFiles` functions. The problem was a looping condition for completing the CLI process to fetch StaticHttp data.
  See [#120](https://github.com/dillonkearns/elm-pages/pull/120).

## [5.0.1] - 2020-05-13

### Fixed

- Make sure the build fails when there are `Err` results in any markdown content. Fixes [#102](https://github.com/dillonkearns/elm-pages/issues/102).
  This fix also means that any markdown errors will cause the error overlay in the dev server to show.

## [5.0.0] - 2020-05-11

### Changed

- Use builder pattern to build application. In place of the old `Pages.Platform.application`, you now start building an application config with `Pages.Platform.init`, and complete it with `Pages.Platform.toProgram`. You can chain on some calls to your application builder. This is handy for creating plugins that generate some files and add some head tags using `withGlobalHeadTags`.
- The `documents` key is now a List of records. The `Pages.Document` module has been removed entirely in place of a simplified API. `elm-markup` files no longer have any special handling
  and the direct dependency was removed from `elm-pages`. Instead, to use `elm-markup` with `elm-pages`, you now wire it in as you would with a markdown parser or any other document handler.
- Replaced `generateFiles` field in `Pages.Platform.application` with the `Pages.Platform.withFileGenerator` function.
- Instead of using the `zwilias/json-decode-exploration` package directly to build up optimizable decoders, you now use the `OptimizedDecoder` API. It provides the same drop-in replacement,
  with the same underlying package. But it now uses a major optimization where in your production build, it will run a plain `elm/json` decoder
  (on the optimized JSON asset that was produced in the build step) to improve performance.

### Added

- Added `Head.Seo.structuredData`. Check out Google's [structured data gallery](https://developers.google.com/search/docs/guides/search-gallery) to see some examples of what structured
  data looks like in rich search results that it provides. Right now, the API takes a simple `Json.Encode.Value`. In the `elm-pages` repo, I have an example API that I use,
  but it's not public yet because I want to refine the API before releasing it (and it's a large undertaking!). But for now, you can add whatever structured data you need,
  you'll just have to be careful to build up a valid format according to schema.org.
- `Pages.Directory.basePath` and `Pages.Directory.basePathToString` helpers.
- You can now use `StaticHttp` for your generated files! The HTTP data won't show up in your production bundle, it will only be used to produce the files for your production build.
- Added `Pages.PagePath.toPath`, a small helper to give you the path as a `List String`.

## [4.0.1] - 2020-03-28

### Added

- You can now host your `elm-pages` site in a sub-directory. For example, you could host it at mysite.com/blog, where the top-level mysite.com/ is hosting a different app.
  This works using [HTML `<base>` tags](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/base). The paths you get from `PagePath.toString` and `ImagePath.toString`
  will use relative paths (e.g. `blog/my-article`) instead of absolute URLs (e.g. `/blog/my-article`), so you can take advantage of this functionality by just making sure you
  use the path helpers and don't hardcode any absolute URL strings. See https://github.com/dillonkearns/elm-pages/pull/73.

## [4.0.0] - 2020-03-04

### Changed

- `StaticHttp.stringBody` now takes an argument for the MIME type.

### Added

- `StaticHttp.unoptimizedRequest` allows you to decode responses of any type by passing in a `StaticHttp.Expect`.
- `StaticHttp.expectString` can be used to parse any values, like XML or plaintext. Note that the payload won't be stripped
  down so be sure to check the asset sizes that you're fetching carefully.

## [3.0.2] - 2020-02-03

### Fixed

- Fixed an issue where "Missing content" message flashed for the root page.
- Scroll up to the top of the page on page navigations (Elm's core Browser.application doesn't do this automatically). This change
  preserves the behavior for navigating to anchor links, so you can still go to a fragment and it will take you to the appropriate part
  of the page without scrolling to the top in those cases.

## [3.0.1] - 2020-01-30

### Changed

- Pass allRoutes into pre-rendering for https://github.com/dillonkearns/elm-pages/pull/60.

## [3.0.0] - 2020-01-25

### Changed

- Added URL query and fragment in addition to the PagePath provided by `init` and `onPageChange`.
  See [#39](https://github.com/dillonkearns/elm-pages/pull/39). The new data structure used looks like this:

```elm
    { path : PagePath Pages.PathKey
    , query : Maybe String
    , fragment : Maybe String
    }
```

## [2.0.0] - 2020-01-25

### Added

- There's a new `generateFiles` endpoint. You pass in a function that takes a page's path,
  page metadata, and page body, and that returns a list representing the files to generate.
  You can see a working example for elm-pages.com, here's the [entry point](https://github.com/dillonkearns/elm-pages/blob/master/examples/docs/src/Main.elm#L76-L92), and here's where it
  [generates the RSS feed](https://github.com/dillonkearns/elm-pages/blob/master/examples/docs/src/Feed.elm).
  You can pass in a no-op function like `\pages -> []` to not generate any files.

## [1.1.3] - 2020-01-23

### Fixed

- Fix missing content flash (that was partially fixed with [#48](https://github.com/dillonkearns/elm-pages/pull/48)) for
  some cases where paths weren't normalized correctly.

## [1.1.2] - 2020-01-20

### Fixed

- "Missing content" message no longer flashes between pre-rendered HTML and the Elm app hydrating and taking over the page. See [#48](https://github.com/dillonkearns/elm-pages/pull/48).

## [1.1.1] - 2020-01-04

### Fixed

- Don't reload pages when clicking a link to the exact same URL as current URL. Fixes [#29](https://github.com/dillonkearns/elm-pages/issues/29).

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
  this in the application config record: `Pages.Platform.application { internals = Pages.internals, ... <other fields> }`.
- Add init argument and user Msg for initial PagePath and page changes (see [#4](https://github.com/dillonkearns/elm-pages/issues/4)).

## [1.0.1] - 2019-11-04

### Fixed

- Generate files for extensions other than `.md` and `.emu` (fixes [#16](https://github.com/dillonkearns/elm-pages/issues/16)).
  As always, be sure to also use the latest NPM package.
