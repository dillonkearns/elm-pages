# Changelog [![npm](https://img.shields.io/npm/v/elm-pages.svg)](https://npmjs.com/package/elm-pages)

All notable changes to
[the `elm-pages` npm package](https://www.npmjs.com/package/elm-pages)
will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.12] - 2022-12-02

### Added

- Adds back `elm-pages codegen` command to generate code without compiling or running a build.

## [2.1.9] - 2021-08-27

### Added

- Runs a special `elm-review` config to give better actionable errors for the user instead of error messages pointing to generated code. Note: this now requires `elm-review` to be on the PATH when running `elm-pages`.

## [2.1.8] - 2021-08-25

### Fixed

- `</script>` tags within DataSource's are now escaped correctly on the pre-rendered HTML. Thank you [@danmarcab](https://github.com/danmarcab) for the report and the fix! See [#207](https://github.com/dillonkearns/elm-pages/pull/207).

## [2.1.7] - 2021-08-17

### Fixed

- Check for `elm` and `elm-optimize-level-2` executables before running build step to report better error message.
- Removed `elm-optimize-level-2` as a dependency since the user needs to install it as a `devDependency` in their project anyway to make the binary available.

## [2.1.6] - 2021-08-15

### Fixed

- `undefined` errors that were printed in `elm-pages build` are now showing the correct error output.

## [2.1.4] - 2021-08-02

### Fixed

- Refer to latest NPM version in init template.

## [2.1.3] - 2021-08-02

### Fixed

- Cleaned up error printing in dev server and build to prevent some errors when presenting failure messages.

## [1.5.5] - 2020-02-16

### Fixed

- Use `cross-spawn` in the beta build to support running on Windows. Thank you @Y0hy0h for fix [#161](https://github.com/dillonkearns/elm-pages/pull/161)!

## [1.5.4] - 2020-11-02

### Fixed

- Use a more reliable codegeneration order for the elm-pages dev server to make sure changes hot reload correctly.

## [1.5.3] - 2020-10-29

### Fixed

- 1.5.2 didn't end up fixing the infinite loop in `elm-pages develop`. It's now properly fixed.
- No more double-builds on changes for `elm-pages develop` webpack dev server, so page changes are faster.

## [1.5.2] - 2020-10-28

### Fixed

- Fixed infinite loop in `elm-pages develop` from the new generated beta code.

## [1.5.1] - 2020-10-27

### Fixed

- Add missing closing tag for `<head>` in beta build command output.
- Make sure to add `/` separator for `content.json` file requests in beta build's JS code.

## [1.5.0] - 2020-10-26

### Added

- Support for `elm-pages-beta` no-webpack build command (see Elm package [release notes for 7.0.0](https://github.com/dillonkearns/elm-pages/blob/master/CHANGELOG-ELM.md#700---2020-10-26)).

## [1.4.3] - 2020-08-17

### Added

- `elm-pages build --skip-dist` option allows you to build the generated Elm code and
  check for errors without running the pre-rendering steps. Thank you [@sparksp](https://github.com/sparksp)!
  See https://github.com/dillonkearns/elm-pages/pull/123/files.

### Fixed

- Added headers to the dev server that prevent Safari from serving up stale data. Thank you
  Kevin Yank for reporting the issue!

## [1.4.2] - 2020-07-14

### Added

- Added dimensions to static images: https://github.com/dillonkearns/elm-pages/pull/110.

## [1.4.1] - 2020-06-16

### Fixed

- Fix `static` folder behavior in Windows, see [#118](https://github.com/dillonkearns/elm-pages/pull/118) (thank you [Y0hy0h](https://github.com/Y0hy0h)!).
- Make sure that process exits with non-zero status on error so build fails when there are errors in the build. See [#121](https://github.com/dillonkearns/elm-pages/pull/121).

## [1.4.0] - 2020-05-11

### Added

- Added hot content reloading to the dev server! That means that you no longer have to restart your dev server if you add/change a StaticHttp request. You don't even
  have to reload your browser! It will automatically load in the new data, while keeping your application state. Your markdown (or other format) data, and metadata,
  from the `content` folder will also load for you without having to restart the dev server or refresh your browser! You'll see a loading indicator to show you when
  the dev server is loading a new change.
- `elm-pages` now uses an in-memory cache for `StaticHttp` requests. That means that the dev server won't redo requests that were already being performed as you change
  code with the dev server running.
  frontmatter in files in the `content/` folder and save with the dev server running.
- Files are re-generated as you change your Elm code. Just refresh the generated file URL while running your dev server, and you'll always see the latest version! Note:
  there's still an issue where if you no longer generate a file, you'll need to restart your dev server to get a 404 when hitting that URL.

### Changed

- Uses Terser instead of GoogleClosureCompiler to minify the JavaScript bundle in production. GoogleClosureCompiler was causing some issues for Windows users when
  they ran `elm-pages build` because that dependency has known issues on Windows. See [#90](https://github.com/dillonkearns/elm-pages/pull/90). Thank you very much
  to [Johannes Maas](https://github.com/Y0hy0h) for the PR!

### Fixed

- Fixed an issue with the dev server not noticing changes to `.emu` files. See [#78](https://github.com/dillonkearns/elm-pages/issues/78). `elm-markup` files, and files with
  the `.emu` extension, are handled exactly like any other files in the `content/` folder now. This simplifies the API, and the internal logic is simpler and less error-prone.
- Decode errors now show error messages correctly for `StaticHttp.unoptimizedRequest`s.
- `elm-pages` will generate the `gen/Pages.elm` module whether or not there are any errors in the build. This was problematic before this fix because you often need
  the generated file in order to get it compiling in the first place. So it can cause a chicken-and-egg problem.
- `elm-pages` is now more reslient to errors so you don't have to restart the dev server as often. There is still a known issue where a dev server restart is needed
  when you have unfinished `---` for your

## [1.3.0] - 2020-03-28

### Added

- You can now host your `elm-pages` site in a sub-directory. For example, you could host it at mysite.com/blog, where the top-level mysite.com/ is hosting a different app.
  This works using [HTML `<base>` tags](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/base). The paths you get from `PagePath.toString` and `ImagePath.toString`
  will use relative paths (e.g. `blog/my-article`) instead of absolute URLs (e.g. `/blog/my-article`), so you can take advantage of this functionality by just making sure you
  use the path helpers and don't hardcode any absolute URL strings. See https://github.com/dillonkearns/elm-pages/pull/73.

## [1.2.11] - 2020-03-18

### Fixed

- Triple quoted strings in content files are now escaped properly (see [#26](https://github.com/dillonkearns/elm-pages/issues/26)).
- Fixed a path delimiter bug for Windows. Dev server appears to work smoothly on Windows now. See [#82](https://github.com/dillonkearns/elm-pages/pull/82).
  There's currently an issue with running a production build on windows because of Google Closure Compiler. We're investigating possible fixes.
  A big thank you [@vViktorPL](https://github.com/vViktorPL) for these two fixes!

## [1.2.10] - 2020-02-25

- Turn off offline service worker fallbacks for now. This will likely be revisited
  in the future when I can give it a full treatment. It seemed to cause an issue
  for at least one user of elm-pages, though it may have been related to some
  a Netlify cloudflare plugin that modifies the HTML assets.

## [1.2.9] - 2020-02-18

- Fix an issue with the NPM bundle (see https://github.com/dillonkearns/elm-pages/issues/71).
  Thank you for the fix [@icidasset](https://github.com/icidasset)! 🙏

## [1.2.8] - 2020-02-08

### Fixed

- Colorize elm make output for initial elm-pages build step. See [#66](https://github.com/dillonkearns/elm-pages/issues/66).
  Note, this patch still hasn't propogated through to `elm-webpack-loader` (see https://github.com/elm-community/elm-webpack-loader/issues/166).
  So there may still be non-colorized output for errors as you make changes while the dev server is running.

## [1.2.7] - 2020-02-03

### Fixed

- Don't serve fallback HTML from service worker when a page 404s... only when it fails to load (i.e. when
  you're offline). 404s will go through from the server if you're online now.

## [1.2.6] - 2020-02-03

### Fixed

- Only serve up the root route's HTML as a fallback when you're offline. This fixes the flash of root page content
  when you are online. When you're offline, you will currently still see the root page flash when you load a page,
  but you will be able to navigate to any cached pages as long as their content.json is in the service worker cache.

## [1.2.5] - 2020-01-31

### Fixed

- Make sure that pre-render trigger event fires to fix pre-rendering hanging.

## [1.2.4] - 2020-01-30

### Fixed

- Don't pre-fetch content.json files for unknown paths: https://github.com/dillonkearns/elm-pages/pull/60.
- Fix race condition where pre-rendered content sometimes didn't have body: https://github.com/dillonkearns/elm-pages/pull/62.

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

\*Check out [this upgrade checklist](https://github.com/dillonkearns/elm-pages/blob/master/docs/upgrade-guide.md#upgrading-to-elm-package-110-and-npm-package-113) for more details and steps for upgrading your project.

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
