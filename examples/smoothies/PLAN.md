# Smoothies Example: Modernization & Test Suite Plan

## Goal

Modernize the smoothies shopping cart example to current elm-pages APIs, then add a test suite that showcases the **optimistic UI** pattern from the [Declarative Server State blog post](~/Documents/Obsidian/Declarative%20Server%20State.md). The tests should demonstrate that you can build a full-stack Elm app with real server interactions -- authentication, a persisted shopping cart, optimistic UI -- and test it all with confidence.

## Blog Post Context

The smoothies app demonstrates "declarative server state" -- the idea that server state is a different kind of state that doesn't belong in your `Model`. Key patterns:

- **Data loading with no Model/Msg boilerplate**: `data` function runs on the server, view receives it through `app.data`
- **Session auth via signed cookies**: `MySession.expectSessionDataOrRedirect` reads session, redirects to `/login` if missing
- **Forms as server actions**: HTML forms POST to the server, `action` function handles them
- **Progressive enhancement**: Add `fetcherOnSubmit` / `withConcurrent` for SPA-like behavior without full page reloads
- **Optimistic UI**: `app.concurrentSubmissions` shows pending form data, view overlays it on actual data for instant feedback

The punchline: `Model = {}`, `Msg = NoOp`, `update` is untouched. All server interaction is declarative.

## Current State

The app was built for an early v3 beta of elm-pages. It has ~25 Elm source files with 71 old API usages that need updating. Main issues:

### API Changes Needed

| Old API | New API | Files Affected |
|---------|---------|----------------|
| `Server.Request.Parser` | `Server.Request` (direct, no Parser wrapper) | MySession, all routes |
| `Request.succeed`, `Request.andThen`, `Request.expectFormPost` | Direct `Request` functions on the request parameter | all routes |
| `Form.init { combine, view }` | `Form.form (\field -> { combine, view })` | Index, Login, New, Signup, etc. |
| `Form.toDynamicFetcher`, `Form.initCombined`, `Form.combine` | `Pages.Form.renderStyledHtml`, `Form.Handler.init`, `Form.Handler.with` | Index |
| `Form.renderHtml [] Nothing app data` | `Pages.Form.renderStyledHtml [] (Form.options "id") app` | all form renders |
| `Form.ServerForms`, `Form.runOneOfServerSide` | `Form.Handler`, `Request.formData` | Index action/view |
| `Request.Hasura.backendTask` / `mutationBackendTask` | Needs replacement (see Data Layer below) |  Index, Login, New, etc. |
| `Form.FormData` | Removed (form data is `List (String, String)` now) | Effect |
| `Head.Seo` | `Head` (Seo helpers moved) | various |
| `SharedTemplate` | `Shared.template` pattern changed | Shared |
| `StatefulRoute`/`StatelessRoute` type aliases changed | `RouteBuilder` updated signatures | all routes |
| `init` takes `Maybe PageUrl` | `init` takes `App` | all stateful routes |
| `update` takes `PageUrl` | `update` takes `App` | all stateful routes |
| `view` takes `Maybe PageUrl, Shared.Model, Model, App` | `view` takes `App, Shared.Model` (or with Model for stateful) | all routes |
| `FetchRouteData`, `Submit` Effect variants | Removed (handled by framework) | Effect |
| `Path` | `UrlPath` | Shared, routes |

### Data Layer: Hasura/GraphQL -> Virtual FS

The app uses `Request.Hasura` to talk to a Hasura GraphQL endpoint. For the test suite, we need to replace this with something that works in the virtual FS:

**Current data flow:**
- `Data.Smoothies.selection` -> GraphQL SelectionSet -> Hasura HTTP -> JSON -> `List Smoothie`
- `Data.Cart.selection userId` -> GraphQL SelectionSet -> Hasura HTTP -> JSON -> `Maybe Cart`
- `Data.Cart.addItemToCart quantity userId itemId` -> GraphQL Mutation -> Hasura HTTP
- `Data.User.selection userId` -> GraphQL SelectionSet -> Hasura HTTP -> JSON -> `User`

**Test-compatible replacement options:**

1. **BackendTask.File with JSON** (simplest): Store smoothie data, cart state, and user data as JSON files in the virtual FS. `data` reads them, `action` writes them.

2. **BackendTask.Custom ports** (more realistic): Use custom BackendTask ports for data access, simulate them in tests via `Test.BackendTask.simulateCustom`.

3. **Keep GraphQL but mock HTTP** (preserves structure): Keep the GraphQL selection sets but mock the Hasura HTTP calls via `simulateHttpPost` in tests. This preserves the app structure closest to production.

**Recommended: Option 1 for simplicity.** The test suite's value is in demonstrating the form submission + optimistic UI pattern, not GraphQL integration. JSON files in virtual FS are the simplest path to testable data.

### Simplified Data Model for Tests

```
smoothies.json: [{ "id": "smoothie-1", "name": "Berry Blast", "price": 5, "description": "...", "image": "..." }, ...]
cart-{userId}.json: { "smoothie-1": { "quantity": 2, "pricePerItem": 5 }, ... }
users.json: { "user-1": { "name": "Alice" } }
```

## Test Suite Plan

### Test File: `tests/SmoothieTests.elm`

Tests to write, in order of complexity:

#### 1. `smoothieListTest` -- Data loads and renders
Start at `/`, verify smoothie list renders with names and prices.
Exercises: `data` function, virtual FS, session auth redirect.

#### 2. `loginAndViewSmoothiesTest` -- Session auth flow
Start at `/login`, submit credentials, redirect to `/`, verify smoothies display with user greeting.
Exercises: Session cookies, redirect, data loading with auth.

#### 3. `addToCartTest` -- Form submission updates cart
Click "+" on a smoothie, verify the cart total updates.
Exercises: Form action, cart mutation (virtual FS write), data refresh.

#### 4. `optimisticCartTest` -- THE SHOWCASE TEST
Click "+" on a smoothie, verify the quantity updates IMMEDIATELY (before server confirms).
The key assertion: after clicking "+", the view should show the new quantity BEFORE `resolveEffect` is called. This proves optimistic UI via `concurrentSubmissions`.

```elm
optimisticCartTest : PagesProgram.Test
optimisticCartTest =
    PagesProgram.test "optimistic cart update"
        (TestApp.start "/"
            (BackendTaskTest.init
                |> BackendTaskTest.withFile "smoothies.json" smoothieData
                |> BackendTaskTest.withFile "cart-user1.json" "{}"
                |> BackendTaskTest.withEnv "SESSION_SECRET" "test"
            )
        )
        [ PagesProgram.ensureViewHas [ text "Berry Blast" ]
        , PagesProgram.ensureViewHas [ text "Checkout (0)" ]
        , -- Click "+" on Berry Blast
          PagesProgram.clickButton "+"
        , -- IMMEDIATELY see the optimistic update (before server confirms)
          PagesProgram.ensureViewHas [ text "Checkout (1)" ]
        , -- Cart total shows the price
          PagesProgram.ensureViewHas [ text "$5" ]
        ]
```

#### 5. `multipleOptimisticUpdatesTest` -- Concurrent submissions
Click "+" multiple times rapidly, verify each click is reflected immediately.
Exercises: Multiple concurrent submissions, pending state accumulation.

#### 6. `signoutTest` -- Session clearing
Click "Sign out", verify redirect to login, session cleared.
Exercises: Form action with redirect, session clearing.

## Modernization Steps

### Phase 1: Framework boilerplate (Effect, Shared, View, ErrorPage)
Update the app shell files to current APIs. Use end-to-end example as reference.

### Phase 2: Data layer
Replace `Request.Hasura` and GraphQL with `BackendTask.File` / virtual FS reads/writes.
Update `Data.Smoothies`, `Data.Cart`, `Data.User` to use file-backed data.

### Phase 3: Session/Auth
Update `MySession.elm` to current `Server.Session` API (withSession, withSessionResult).

### Phase 4: Form APIs
Update `Form.init` -> `Form.form`, form rendering, form parsing.
Update `Form.toDynamicFetcher` -> `Pages.Form.withConcurrent`.
Update `Form.initCombined`/`Form.combine` -> `Form.Handler.init`/`Form.Handler.with`.

### Phase 5: Route modules
Update each route's type signatures, imports, and function bodies.
Focus on `Route.Index` first (the main smoothie list with cart).
Then `Route.Login` (auth flow).
Other routes (New, Edit, Profile, etc.) can be updated later or removed if not needed for the test showcase.

### Phase 6: Tests
Create `tests/SmoothieTests.elm` with the test suite described above.
Verify via `elm-pages test`; use `elm-pages dev` and open `/_tests` for the browser viewer.

## Reference: Working Patterns

The `examples/end-to-end` project has working examples of all the patterns we need:

- **Session auth with cookies**: `Route/Login.elm`, `Route/Greet.elm`, `MySession.elm`
- **Concurrent form submission**: `Route/QuickNote.elm` with `Pages.Form.withConcurrent`
- **Form with hidden fields**: `Route/DarkMode.elm`
- **Data refresh after action**: `Route/Feedback.elm`
- **Error pages**: `Route/ErrorHandling.elm`

## Test Framework Features Available

Our test framework (built in this session) provides everything needed:

- `TestApp.start "/path" setup` -- full Platform fidelity
- `PagesProgram.clickButton` -- form submission with hidden fields (via Form.updateWithMsg)
- `PagesProgram.fillIn` -- form field input
- `PagesProgram.ensureViewHas` / `ensureViewHasNot` -- view assertions
- `PagesProgram.ensureBrowserUrl` -- URL assertions after redirects
- `PagesProgram.within` -- DOM scoping for clicking specific product's "+" button
- `BackendTaskTest.withFile` -- virtual FS for data
- `BackendTaskTest.withEnv` -- env vars for session secrets
- Cookie jar -- automatically persists session cookies across requests
- Encrypt/decrypt simulation -- session signing/unsigning via marker pattern
- `elm-pages test` -- headless CI execution
- `elm-pages dev` + `/_tests` -- visual browser debugging

## Key Insight for Optimistic UI Test

The optimistic UI test needs to verify that `concurrentSubmissions` is populated DURING the submission (while the action BackendTask is pending). In our test framework:

1. `clickButton "+"` triggers form submit event
2. Platform processes Submit -> SubmitFetcher effect
3. `processEffectsWrapped` handles SubmitFetcher -> resolves action
4. After action resolves, FetcherComplete is dispatched
5. Data re-resolves with updated virtual FS

The optimistic UI pattern works because the VIEW reads `app.concurrentSubmissions` which shows the pending form data BEFORE the action completes. In our test framework, actions resolve synchronously (via `resolveWithVirtualFs`), so we may need to verify the pattern differently -- perhaps by checking that the view correctly merges pending data with actual data.

If the test framework resolves actions synchronously, the "optimistic" state may not be visible as a separate step. In that case, the test still proves that the data flow works correctly end-to-end, and the visual test runner (`elm-pages dev` + `/_tests`) shows the step-by-step snapshots including the concurrent submission state.
