# `elm-pages` [![Netlify Status](https://api.netlify.com/api/v1/badges/8ee4a674-4f37-4f16-b99e-607c0a02ee75/deploy-status)](https://app.netlify.com/sites/elm-pages/deploys) [![Build Status](https://github.com/dillonkearns/elm-pages/workflows/Elm%20CI/badge.svg)](https://github.com/dillonkearns/elm-pages/actions?query=branch%3Amaster) [![npm](https://img.shields.io/npm/v/elm-pages.svg)](https://npmjs.com/package/elm-pages) [![Elm package](https://img.shields.io/elm-package/v/dillonkearns/elm-pages.svg)](https://package.elm-lang.org/packages/dillonkearns/elm-pages/latest/)

[![Deploy to Netlify](https://www.netlify.com/img/deploy/button.svg)](https://app.netlify.com/start/deploy?repository=https://github.com/dillonkearns/elm-pages-starter)

`elm-pages` is a framework for building an Elm single-page app that is able to seamlessly interface with data from an Elm Backend. `elm-pages` is a hybrid framework, allowing you to define Routes that are either server-rendered
(for more dynamic content with user-specific or request-specific data) or pre-rendered at build-time (for generating static HTML files that are hosted through a CDN). You can mix and match server-rendered and pre-rendered routes in your app.

`elm-pages` also has a command for running pure Elm scripts with a single command. See the [elm-pages Scripts docs page](https://elm-pages-v3.netlify.app/docs/elm-pages-scripts).

## What's new in 12.2

- **[`Tui`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/12.2.1/Tui/)** — build interactive terminal apps as elm-pages scripts. TEA-style `init`/`update`/`view` that renders styled text to the terminal and responds to keyboard, mouse, paste, resize, and time events. `Tui.programOrScript` lets the same script behave interactively in a TTY and as a plain `BackendTask` under CI or when its output is piped.
- **[`Test.PagesProgram`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/12.2.1/Test-PagesProgram/)** — end-to-end tests for elm-pages routes. Drive the real framework runtime through form submissions, optimistic UI, concurrent fetchers, redirects, session cookies, and error pages with simulated HTTP and custom ports. Deterministic, in-process, no browser. Inspired by [elm-program-test](https://package.elm-lang.org/packages/avh4/elm-program-test/latest/).
- **[`Test.Tui`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/12.2.1/Test-Tui/)** — pure Elm tests for TUI programs. Simulate keypresses and mouse events, resolve pending `BackendTask`s with the [`Test.BackendTask`](https://package.elm-lang.org/packages/dillonkearns/elm-pages/12.2.1/Test-BackendTask/) simulators, and assert on screen output.
- **Visual test runner** — `elm-pages dev` serves page tests in the browser at `/_tests`, and `elm-pages test --visual` steps through TUI tests in the terminal. Run tests headlessly with `elm-pages test`.

See [`examples/smoothies/tests/`](https://github.com/dillonkearns/elm-pages/tree/master/examples/smoothies/tests) and [`examples/todos/tests/`](https://github.com/dillonkearns/elm-pages/tree/master/examples/todos/tests) for route tests, and [`examples/end-to-end/script/tests/TuiStarsTests.elm`](https://github.com/dillonkearns/elm-pages/blob/master/examples/end-to-end/script/tests/TuiStarsTests.elm) for a TUI test.

## Getting Started Resources

- [elm-pages Docs Site](https://elm-pages.com/docs)
- [elm-pages site showcase](https://elm-pages.com/showcase/)
- [elm-pages Elm API Docs](https://package.elm-lang.org/packages/dillonkearns/elm-pages/12.2.1/)
- [Quick start repo](https://github.com/dillonkearns/elm-pages-starter) [(live site hosted here)](https://elm-pages-starter.netlify.com)
- [Introducing `elm-pages` blog post](https://elm-pages.com/blog/introducing-elm-pages)
- [`examples` folder](https://github.com/dillonkearns/elm-pages/blob/master/examples/) (includes https://elm-pages.com site source) Use `git clone --recurse-submodules https://github.com/dillonkearns/elm-pages.git` so that there aren't missing files when you try to build the examples.

## Compatibility Key

You will see an error if the NPM and Elm package do not have a matching Compatibility Key. Usually it's best to upgrade to the latest version of both the Elm and NPM
packages when you upgrade. However, in case you want to install versions that are behind the latest, the Compatibility Key is included here for reference.

Current Compatibility Key: 29.
