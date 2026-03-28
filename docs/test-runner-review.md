# Test Runner Review

Date: 2026-03-19

> Historical note:
> This review describes an earlier prototype of the page-test runner.
> Since then, the generated `TestApp` path has moved to `Test.PagesProgram.startPlatform`,
> `elm-pages test-view` now emits a standalone preview shell, and ProgramTest discovery
> has been expanded. Keep that in mind when reading the findings below.

## Executive Summary

The current test-runner work has a strong core idea and a promising low-level API, but it is not yet safe to present as "real elm-pages behavior except for stubbed external I/O."

The biggest gap is the generated route-facing path (`TestApp` + `Test.PagesProgram.Route`). The hand-written `PagesProgram.start { data, init, update, view }` API works for small, self-contained demos, and the existing tests validate that path. But the route adapter currently skips or stubs too much of the actual elm-pages runtime: shared data and shared view composition, page actions, navigation state, concurrent submissions, request context, subscriptions, and most user effects. That means the place where users most want the abstraction to feel "just like elm-pages" is currently the least trustworthy part.

In short: the simple demo layer is working, but the generated route API is still closer to a page-level state machine harness than a faithful elm-pages app harness. That creates a real risk of false positives, false negatives, and user confusion.

## Validation Notes

- I ran `npx elm-test tests/PagesProgramTest.elm tests/RealisticExampleTest.elm`; 19 tests passed.
- I did not find any tracked tests that exercise the generated `TestApp` / `Test.PagesProgram.Route.fromStatefulRoute` path directly.
- I compared the current UX and API against:
  - elm-program-test guidebook: [https://elm-program-test.netlify.app/html](https://elm-program-test.netlify.app/html)
  - Cypress open mode: [https://docs.cypress.io/app/core-concepts/open-mode](https://docs.cypress.io/app/core-concepts/open-mode)
  - Cypress network interception: [https://docs.cypress.io/api/commands/intercept](https://docs.cypress.io/api/commands/intercept)
- I could not locate an official public source for `LendUI/program-test` under that exact name during this review, so the external comparison is anchored mainly on elm-program-test and Cypress.

## Findings

### 1. The generated route-facing API is not yet a faithful elm-pages harness

This is the most important issue.

The generated `TestApp` path promises route-level testing with `PagesProgram.start (TestApp.index {})`, but it does not currently model a real elm-pages page load closely enough to trust its results.

Evidence:

- `generator/src/generate-template-module-connector.js:399-408` hardcodes `sharedData = ()` and converts route view messages with `Html.map (\_ -> crashPlaceholder ())`.
- `src/Test/PagesProgram/Route.elm:53-88` only adapts `route.data`, `route.init`, `route.update`, and `route.view`.
- `generator/src/RouteBuilder.elm:133-173` shows what a real `StatefulRoute` and `App` actually need: `action`, `subscriptions`, `url`, `navigation`, `concurrentSubmissions`, `pageFormState`, and real `Shared.Data`.
- `generator/src/SharedTemplate.elm:14-40` shows that a real elm-pages render also goes through `Shared.template.view` and `Shared.template.data`.

Practical consequences:

- Shared layout is missing. Route tests do not go through `Shared.template.view`, so anything rendered there is invisible to this runner. A standard template menu in `generator/template/app/Shared.elm:84-110` would not be exercised at all.
- Shared data is wrong. `sharedData = ()` is only valid for apps whose `Shared.Data` really is unit. In the docs example, `examples/docs/app/Shared.elm:36-38,86-88` defines non-unit shared data, and `examples/docs/app/Route/Docs/Section__.elm:206-217` uses `app.sharedData` in the route view. The generated test adapter cannot represent that correctly.
- Request/app context is stubbed. `src/Test/PagesProgram/Route.elm:55-60,94-103,154-171` hardcodes an empty path, a fixed GET request to `/`, no headers, no cookies, no URL, no action data, no navigation, and no concurrent submissions.
- Route actions are not modeled. `fromStatefulRoute` only resolves `route.data` (`src/Test/PagesProgram/Route.elm:63-66`) and `makeApp` sets `action = Nothing` (`src/Test/PagesProgram/Route.elm:159-160`), so form/action flows cannot be trusted.
- Subscriptions are dropped entirely. `StatefulRoute` has a `subscriptions` field (`generator/src/RouteBuilder.elm:147`), but the adapter never uses it.

This is the main reason I would not yet describe the current route-level test API as "equivalent to elm-pages except for mocked outside services."

### 2. The generated route adapter throws away route messages and most route effects

Even if the missing runtime context above were fixed, the generated `TestApp` still discards the two things that make route tests useful: user messages and effects.

Evidence:

- `generator/src/generate-template-module-connector.js:403-406` maps every view message to `crashPlaceholder`.
- `generator/src/generate-template-module-connector.js:411-421` only preserves `Effect.None` and recursively flattens `Effect.Batch`; every other effect becomes `[]`.
- The default template `Effect` type includes `Cmd`, `GetStargazers`, `FetchRouteData`, `Submit`, `SubmitFetcher`, and `SetField` at `generator/template/app/Effect.elm:18-32,97-147`.

Practical consequences:

- Interactive route views are not actually interactable through the generated path because their messages are replaced with a crash placeholder before `Event.simulate` can hand them back to `update`.
- Real route effects silently disappear. A route can return `SubmitFetcher`, `FetchRouteData`, `Cmd`, or any other non-batch effect and the runner will record no pending effect at all.
- That makes false passes likely. The test can continue and even finish green while real runtime work was dropped.

This specific area is a blocker for trusting generated route tests.

### 3. Pending effects are overwritten after every simulated message

There is a concrete correctness bug in the low-level `Test.PagesProgram` pipeline itself.

Evidence:

- `src/Test/PagesProgram.elm:907-916` sets `pendingEffects = newEffects` in `applyMsgWithLabel`.
- `resolveEffect` correctly preserves the rest of the queue with `rest ++ newEffects` at `src/Test/PagesProgram.elm:564-583`.

Why this matters:

- If a page already has unresolved effects and the user triggers another message, the earlier pending effects are dropped.
- `done` only checks the remaining `pendingEffects` queue (`src/Test/PagesProgram.elm:759-768`), so a test can pass after silently forgetting unresolved work.

This is exactly the kind of bug that creates false confidence.

### 4. Browser semantics are much weaker than real user interaction

The interaction helpers are nice and readable, but they currently ignore several browser-level constraints that elm-program-test and Cypress both take seriously.

Evidence:

- `clickButton` only finds the first `<button>` containing text and simulates a click directly: `src/Test/PagesProgram.elm:281-297`.
- `fillIn` and `check` target raw `id`s only: `src/Test/PagesProgram.elm:349-362,477-502`.
- `clickLink` swallows every simulation error and returns the unchanged state: `src/Test/PagesProgram.elm:430-438`.
- The vendored elm-program-test source explicitly checks for disabled buttons and supports richer targeting such as labels, aria labels, textarea, select, and scoped queries: `examples/end-to-end/elm-program-test-src/ProgramTest.elm:890-970,1227-1388`.
- Cypress emphasizes actionability, snapshots, and request visibility in open mode: [open mode docs](https://docs.cypress.io/app/core-concepts/open-mode). Cypress action commands also retry and respect actionability rules, for example `.check()` and `.click()` style commands in the API docs and guides.

Practical consequences:

- Disabled buttons are likely clickable in tests even when the browser would block them.
- `clickLink` can silently do nothing when the link is missing or lacks the expected handler, which is especially dangerous because the comment says it records a snapshot, but the implementation just returns `ProgramTest state`.
- Label-driven forms are harder to test than they need to be, which pushes users toward brittle IDs instead of user-facing semantics.
- There is no route/navigation-level assertion surface comparable to `ensureBrowserUrl`, `routeChange`, or browser-history checks from elm-program-test.

Compared to the stated goal, this layer still feels like synthetic message dispatch, not user interaction with a browser-like runtime.

### 5. Data/effect setup is too limited for real elm-pages routes

`Test.PagesProgram.start` claims to use the same route fields and only fake external I/O, but it has no way to pass a `Test.BackendTask` setup. That is a serious limitation because `Test.BackendTask` itself is explicitly virtual-state based.

Evidence:

- `start` always uses `BackendTaskTest.fromBackendTask config.data` with no setup: `src/Test/PagesProgram.elm:166-172`.
- `resolveEffect` also reconstructs effects with `BackendTaskTest.fromBackendTask` and no setup: `src/Test/PagesProgram.elm:564-571`.
- `Test.BackendTask` documents that files, globbing, env vars, time, random, which, and DB are virtual and need explicit setup via `withFile`, `withEnv`, `withTime`, `withDb`, etc.: `src/Test/BackendTask.elm:35-117`.
- The data-phase simulation type only supports HTTP GET/POST: `src/Test/PagesProgram.elm:119-121`.

Practical consequences:

- Routes that depend on project files, globbing, env vars, DB state, time, or random values are not naturally runnable through this API.
- There is no `startWith` or equivalent hook to seed the virtual environment.
- The docs at `src/Test/PagesProgram.elm:12-15,141-147` currently over-promise what "same logic as the real framework" means.

### 6. FatalError handling in the data phase is currently unsafe

When the page data `BackendTask` finishes with a `FatalError`, the runner does not surface a real failure state. It builds a `Ready` state by recursively crashing for the data value.

Evidence:

- `src/Test/PagesProgram.elm:988-996` uses `crashData err` to feed both `init` and `view`.
- `crashData` is an infinite recursive placeholder at `src/Test/PagesProgram.elm:1061-1063`.

Practical consequences:

- A route/data failure does not become a clean, inspectable test failure.
- Depending on what `init` or `view` touches, the runner can blow up in confusing ways instead of showing a faithful elm-pages failure or error page path.

This is another area where false negatives and confusing DX are likely.

### 7. The command surface and dev-server integration are still confusing

From a user's perspective, the testing story currently feels fragmented.

Evidence:

- `generator/src/cli.js:129-149` splits `elm-pages test` (TUI stepper) from `elm-pages test-view` (browser viewer).
- The only tracked "how to open the visual runner" note I found is the inline comment in `examples/end-to-end/tests/PageTests.elm:8-10`.
- I did not find README or docs pages that explain the relationship between `elm-pages test`, `elm-pages test-view`, and `elm-pages dev` + `/__test-viewer`.

Practical consequences:

- A new user is likely to try `elm-pages test` for page tests and land in the wrong tool.
- The fact that the dev server also exposes a browser viewer is helpful, but it is not discoverable enough yet.
- The two paths also feel inconsistent: TUI tests have a first-class command, while page tests are split between a separate command and a dev-server route.

### 8. Test discovery and failure presentation are brittle

There are several medium-severity DX issues around discovery and the browser viewer.

Evidence:

- `generator/src/commands/shared.js:988-993` only matches single-line type annotations when discovering `ProgramTest` values. Multi-line annotations are easy to miss.
- `generator/src/commands/test-view.js:52-84` auto-discovers only `tests/**/*.elm`, even though `resolveTestInputPath` understands `snapshot-tests/src`.
- The dev-server viewer returns HTML even when no tests were compiled or compilation failed:
  - missing-tests early return: `generator/src/dev-server.js:347-349`
  - compilation errors logged as non-fatal: `generator/src/dev-server.js:420-428`
  - HTML still served with `/test-viewer.js`: `generator/src/dev-server.js:317-318,432-458`
- `Snapshot.rerender` is documented as letting the viewer re-render at a different size in `src/Test/PagesProgram.elm:86-100`, but the viewer only renders `snapshot.body` and never uses `rerender`: `src/Test/PagesProgram/Viewer.elm:317-325`.

Practical consequences:

- Valid tests can be skipped by discovery.
- The browser viewer can degrade into a blank or broken page instead of presenting a clear compiler/runtime error.
- The visual runner does not yet deliver viewport/responsive debugging even though the snapshot model is already trying to support it.

## What Is Working Well

- The low-level hand-authored API in `Test.PagesProgram` is genuinely pleasant for small, self-contained page-state tests.
- The current tests cover that simple path reasonably well, and the core pipeline is easy to read.
- The snapshot/timeline concept is strong. The viewer already has the right basic primitives: named tests, per-step snapshots, keyboard navigation, and an optional model pane.
- The examples in `examples/end-to-end/tests/PageTests.elm` are approachable and show the intended ergonomics clearly.

## Comparison To Inspirations

### elm-program-test

The new API is clearly inspired by elm-program-test's readability, which is a good direction. But elm-program-test is still stronger on both fidelity and ergonomics:

- It models browser concepts explicitly: base URL, route changes, browser history, navigation assertions, and simulated effects/subscriptions.
- Its DOM API is more user-facing and accessibility-oriented. The guidebook example uses `fillIn "postcode" "Postal Code" "0000"` rather than a raw ID, and the source supports labels, aria labels, textarea, select, scoped queries, and disabled-element checks.
- It exposes lower-level escape hatches without making the happy path brittle.

The current `Test.PagesProgram` keeps the nice pipeline feel, but today it covers a much smaller and less faithful slice of the real runtime.

### Cypress

Cypress is useful inspiration less because the APIs should match and more because its runner feels trustworthy:

- Open mode gives you a command log, DOM snapshots, URL restoration, pinned snapshots, visible network events, and a dedicated instrument panel for routes/stubs/spies.
- `cy.intercept()` supports request assertions, response stubbing, request mutation, redirects, and network errors.
- The runner is explicit about what happened and why, which reduces "green but I don't trust it."

The current visual runner is a good first step, but it is still a snapshot browser. It does not yet offer request/effect inspection, assertion highlighting, viewport controls, or browser/runtime event visibility at the level Cypress users expect from a polished runner.

## Recommended Direction

### Near-Term

1. Fix the correctness bugs before expanding the surface area.
   - Preserve pending effects in `applyMsgWithLabel`.
   - Make data-phase `FatalError`s become explicit, inspectable failures.
   - Stop swallowing all `clickLink` failures.

2. Re-scope the public promise immediately.
   - Document `Test.PagesProgram.start` as a low-level page-state harness, not a fully faithful route/app runner.
   - Explicitly say which parts of elm-pages are not modeled yet.

3. Improve the browser semantics of the current API.
   - Respect disabled/actionability checks.
   - Prefer label- or role-based queries in addition to IDs.
   - Add textarea/select support and a custom event escape hatch if this API stays public.

### Architectural

1. Replace the generated route adapter with a real app harness built on the platform layer.
   - The most promising precedent is already in the repo: `examples/hello/tests/Tests.elm:80-153` creates a high-fidelity app test by driving `Pages.Internal.Platform`.
   - That approach resolves shared data, injects encoded response data, runs `Platform.init/update/view`, and simulates browser navigation explicitly.

2. Make route tests go through real shared composition.
   - Resolve `Shared.template.data`.
   - Run `Shared.template.init/update/view`.
   - Preserve `Shared.Model`, `Shared.Msg`, `onPageChange`, and shared subscriptions.

3. Model the real app context instead of stubbing it.
   - Request URL, method, headers, cookies, `app.path`, `app.url`, `app.action`, navigation state, and concurrent submissions should all be first-class.

4. Expose configurable test setup for BackendTask-backed state.
   - A `startWith` or `withTestSetup` API would let users seed files, env, DB, time, and random values using the already-good `Test.BackendTask` machinery.

### UX

1. Unify the mental model for commands.
   - Consider whether page tests should also live under `elm-pages test`, with mode detection or a subcommand that is easier to discover.

2. Make the dev-server viewer fail loudly and helpfully.
   - Show compile errors in the browser instead of serving a broken shell.
   - Tell the user when no `ProgramTest` values were discovered.

3. Keep investing in the viewer.
   - Request/effect panel
   - assertion failure highlight
   - pinned step details
   - viewport controls using `Snapshot.rerender`
   - visible URL / route / pending effect state

## Bottom Line

I would treat the current implementation as a promising prototype for a polished elm-pages page-test experience, not as a finished or fully trustworthy route-test harness.

If the goal is "the only difference is mocked outside-world responses," the next milestone should be fidelity, not more viewer features. Once the runner is truly going through the real elm-pages runtime layers, the existing snapshot UI can become a very compelling user-facing tool.
