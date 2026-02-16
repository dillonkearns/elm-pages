# Persistent Data Handling Plan

## Overview

The data narrowing system optimizes client bundles by eliminating ephemeral fields from the `Data` type. Fields only used in `View.freeze` or `head` contexts don't need to be sent to the client at runtime.

## Architecture

### Two-Transform System

1. **Client transform** (`StaticViewTransform.elm`): Analyzes field usage, narrows `Data` type, generates `Ephemeral` type alias
2. **Server transform** (`ServerDataTransform.elm`): Identifies ephemeral fields, generates `ephemeralToData` conversion function

Both transforms MUST agree on which fields are ephemeral. Disagreement causes bytes decode errors at runtime.

### Analysis Strategy

**Approach**: Mark all fields as Ephemeral initially, then identify Persistent fields through usage analysis.

A field is **Persistent** if it's accessed in a client context (view body, non-freeze expressions). A field is **Ephemeral** if it's ONLY accessed in freeze/head contexts.

## Critical Constraint

**When uncertain, bail out and keep fields persistent.**

- De-optimized output = acceptable (larger bundle, but works correctly)
- Incorrectly optimized = BUG (bytes decode error at runtime)

The system is conservative by design. If field tracking is uncertain for any reason, all fields remain persistent.

## Supported Patterns

### Direct Field Access Patterns

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `app.data.field` in freeze/head | ✅ Working | `extractAppDataFieldName` in PersistentFieldTracking |
| `app.data \|> .field` | ✅ Working | `extractAppDataPipeAccessorField` |
| `.field <\| app.data` | ✅ Working | Same function, handles both pipe directions |
| `.field app.data` | ✅ Working | `extractAppDataAccessorApplicationField` |
| `app.data.nested.field` | ✅ Working | Tracks top-level field (e.g., "nested") |

### Let Binding Patterns

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `let title = app.data.title in ...` | ✅ Working | `fieldBindings` tracking in StaticViewTransform |
| `let { title, body } = app.data in ...` | ✅ Working | `extractAppDataBindingsFromLet` |
| `let d = app.data in d.title` | ✅ Working | `appDataBindings` tracking |

### Helper Function Analysis

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `renderContent : Data -> Html` with `data.field` | ✅ Working | `analyzeHelperFunction` |
| `extractTitle { title } = title` (destructuring) | ✅ Working | `extractRecordPatternFields` |
| `helper data = data \|> .field` | ✅ Working | `analyzeFieldAccessesWithAliases` |
| `helper data = .field data` | ✅ Working | Same analysis |
| Let-bound aliases: `let d = data in d.title` | ✅ Working | `extractAliasesFromLetDeclarations` |
| Chained aliases: `let d = data in let e = d in e.title` | ✅ Working | Recursive alias tracking |
| Function aliases: `myRender = renderContent` | ✅ Working | `extractSimpleFunctionReference` + `resolveHelperWithAliases` |
| Chained function aliases: `a = b`, `b = actualHelper` | ✅ Working | Recursive alias chain resolution |
| Helper forwarding: `wrapper data = inner data` | ✅ Working | `extractHelperDelegation` + `resolveDelegations` |
| Multi-parameter helpers: `formatTitle prefix data = ...` | ✅ Working | `analyzeParameter` + `appDataArgIndex` tracking |
| Case with record pattern: `case data of { title } -> title` | ✅ Working | `extractCasePatternFields` in `analyzeFieldAccessesWithAliases` |
| Case with variable pattern: `case data of d -> d.title` | ✅ Working | `extractCaseVariablePatternBindings` + `appDataBindings` tracking |
| Let-bound helpers: `let fn data = data.field in fn app.data` | ✅ Working | `analyzeHelperFunction` on LetFunction declarations |

### Inline Lambda Analysis

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `(\d -> d.title) app.data` | ✅ Working | `analyzeInlineLambda` in checkAppDataPassedToHelper |
| `app.data \|> (\d -> d.title)` | ✅ Working | `checkAppDataPassedToHelperViaPipe` |
| `(\d -> d.title) <\| app.data` | ✅ Working | Same as pipe handling |
| Record destructuring: `(\{ title } -> title) app.data` | ✅ Working | Pattern analysis in `analyzeInlineLambda` |

### Pipe with Partial Application

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `app.data \|> helperFn` | ✅ Working | `checkAppDataPassedToHelperViaPipe` with argIndex 0 |
| `app.data \|> formatHelper "prefix"` | ✅ Working | Partial application detection, argIndex = number of applied args |
| `helperFn <\| app.data` | ✅ Working | Same as forward pipe, argIndex 0 |
| `formatHelper "prefix" <\| app.data` | ✅ Working | Same as forward pipe with partial application |

### Pipe Chains with Further Transformations

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `app.data \|> .title \|> String.toUpper` | ✅ Working | Field access tracked before subsequent transforms |
| `app.data.title \|> String.toUpper` | ✅ Working | Direct field access tracked regardless of pipe target |

### Function Composition Patterns

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `app.data \|> (.title >> String.toUpper)` | ✅ Working | `extractAccessorFromExpr` extracts field from first operand of `>>` |
| `app.data \|> (String.toUpper << .title)` | ✅ Working | `extractAccessorFromExpr` extracts field from second operand of `<<` |
| `(.title >> fn) <\| app.data` | ✅ Working | Same as forward pipe with composition |

**Note**: Function composition with record accessors is tracked by recognizing that `.field >> transform` or `transform << .field` effectively extracts a field first. The `isRecordAccessFunction` helper identifies these patterns so they're handled as field accesses rather than unknown function calls.

### Nested Local Function Applications

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `outer (inner app.data)` where `inner` is local | ✅ Working | `isAppDataPassedDirectlyToInnerCall` in `classifyAppDataArguments` |
| `String.toUpper (extractTitle app.data)` | ✅ Working | Inner call tracked, outer receives result only |
| `(localFn app.data)` parenthesized | ✅ Working | `ParenthesizedExpression` unwrapping in classification |

**Note**: When `app.data` is passed to a local function inside another function call, like `outer (inner app.data)`, the system now tracks through `inner` to determine which fields are used. The key insight is that `outer` receives the *result* of `inner app.data` (not `app.data` itself), so field tracking happens on the inner call.

### Control Flow Patterns

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `if app.data.isPublished then app.data.title else "Draft"` | ✅ Working | All field accesses in condition and branches tracked |
| `case app.data.status of Published -> app.data.title` | ✅ Working | Field access on case subject + branches tracked |

**Note**: `case app.data of ...` (matching on app.data itself with constructor patterns) bails out safely - see Safe Fallback Patterns. But `case app.data.field of ...` (matching on a field value) works correctly.

### Field Accesses in Data Structures

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `[ app.data.title, app.data.subtitle ]` | ✅ Working | Individual field accesses tracked, even in list literals |
| `( app.data.title, app.data.body )` | ✅ Working | Individual field accesses tracked in tuples |
| `String.join ", " [ app.data.title, app.data.subtitle ]` | ✅ Working | Fields tracked before being passed to function |

**Note**: This is different from `[ app.data ]` (putting the entire app.data in a list), which bails out - see Safe Fallback Patterns. Individual field accesses are tracked; wrapping app.data itself is not.

### RouteBuilder Integration

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `head = \app -> [...]` lambdas | ✅ Working | Head function body tracking |
| Non-conventional names: `{ head = seoTags }` | ✅ Working | `routeBuilderHeadFn` extraction |
| Data function stubbing | ✅ Working | `dataFunctionBodyRange` tracking |

### Client Function Tracking (init/update)

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `init` function field access | ✅ Working | `findAppParamIndex` finds App parameter position |
| `update` function field access | ✅ Working | Same as init - App param found via type signature |
| Different App param names: `static`, `app` | ✅ Working | Extracted from correct parameter position |

**Note**: The `init` and `update` functions have different signatures than `view`:
- `view`: App is typically the first parameter
- `init`: App is typically the third parameter (after `Maybe PageUrl`, `Shared.Model`)
- `update`: App is typically the third parameter (after `PageUrl`, `Shared.Model`)

The system finds the App parameter by analyzing the type signature to locate `App Data ActionData RouteParams`.

### Code Examples

```elm
-- Direct field access in freeze/head
view app = { body = [ View.freeze (render app.data.body) ] }

-- Pipe with accessor function (tracks specific field)
view app = { title = app.data |> .title, body = [] }

-- Helper functions with Data parameter (analyzed for field usage)
renderContent : Data -> Html Never  -- Changed to Ephemeral automatically
renderContent pageData = renderMarkdown pageData.body

-- Helper functions with record destructuring pattern (precise tracking)
-- The pattern explicitly declares which fields are needed
extractTitle { title } = title

-- Helper functions using accessor patterns (tracks specific field)
-- All these are equivalent and properly tracked:
extractTitle data = data.title         -- direct field access
extractTitle data = data |> .title     -- pipe with accessor
extractTitle data = .title <| data     -- backward pipe with accessor
extractTitle data = .title data        -- accessor function application

-- Helper functions with let-bound aliases (tracks through alias)
-- The alias is tracked and field accesses on it are properly attributed
extractTitle data =
    let
        d = data     -- d is tracked as alias for data
    in
    d.title          -- tracked as accessing data.title

-- Chained aliases also work
extractTitle data =
    let d = data in
    let e = d in
    e |> .title      -- tracked as accessing data.title

-- Function aliases (myRender is alias to renderContent)
renderContent data = data.body
myRender = renderContent  -- alias is tracked
view app = myRender app.data  -- fields from renderContent are properly tracked

-- Chained function aliases
renderContent data = data.body
aliasB = renderContent
aliasC = aliasB  -- alias chain: aliasC -> aliasB -> renderContent
view app = aliasC app.data  -- resolves entire chain

-- Helper forwarding (wrapper delegates to inner helper)
-- Useful for composing helper functions while maintaining field tracking
innerHelper data = data.title
wrapperHelper data = innerHelper data  -- forwards data to innerHelper
view app = wrapperHelper app.data  -- tracks title from innerHelper

-- Multi-parameter helpers (data in any position)
formatTitle prefix data = prefix ++ data.title  -- data is second param
view app = formatTitle "Hello: " app.data  -- tracks title on second arg

-- Pipe with partial application (data piped to partially applied helper)
formatTitle prefix data = prefix ++ data.title  -- data is second param
view app = app.data |> formatTitle "Hello: "  -- same as above, via pipe

-- Helper functions with case and record pattern (precise tracking)
-- The record pattern in case explicitly declares which fields are needed
extractTitle data =
    case data of
        { title } -> title
view app = extractTitle app.data  -- tracks only title as used

-- Case with variable pattern (field accesses on binding are tracked)
-- This works in both view functions and helper functions
extractTitle data =
    case data of
        d -> d.title  -- tracks title via field access on d
view app = extractTitle app.data  -- or: case app.data of d -> d.title

-- Inline lambdas (analyzed in place, no helper function needed)
view app = { title = (\d -> d.title) app.data, body = [] }

-- Inline lambdas with pipe operator
view app = { title = app.data |> (\d -> d.title), body = [] }

-- Inline lambdas with record destructuring
view app = { title = (\{ title } -> title) app.data, body = [] }

-- Let-bound helper functions (analyzed just like top-level helpers)
view app =
    let
        extractTitle data = data.title
    in
    { title = extractTitle app.data, body = [] }

-- Let-bound helpers with record destructuring
view app =
    let
        extractTitle { title } = title
    in
    { title = extractTitle app.data, body = [] }

-- Let bindings
let title = app.data.title in ...

-- Record destructuring
let { title, body } = app.data in ...

-- RouteBuilder lambdas
head = \app -> [ title app.data.title ]

-- init function field access (App is 3rd parameter)
-- Fields accessed here are client-used (must be kept in Data type)
init : Maybe PageUrl -> Shared.Model -> App Data ActionData RouteParams -> ( Model, Effect Msg )
init maybePageUrl sharedModel app =
    ( { cachedTitle = app.data.title }, Effect.none )

-- update function field access (App is also 3rd parameter)
update : PageUrl -> Shared.Model -> App Data ActionData RouteParams -> Msg -> Model -> ( Model, Effect Msg )
update pageUrl sharedModel app msg model =
    ( { model | title = app.data.title }, Effect.none )

-- Pipe chain with further transformations
-- Field access is tracked before subsequent transforms
view app =
    { title = app.data |> .title |> String.toUpper
    , body = []
    }

-- Function composition with accessor (forward composition)
-- The accessor .title extracts the field, then String.toUpper transforms it
view app =
    { title = app.data |> (.title >> String.toUpper)
    , body = []
    }

-- Function composition with accessor (backward composition)
-- Same result, just written in the opposite direction
view app =
    { title = app.data |> (String.toUpper << .title)
    , body = []
    }

-- If expressions track all field accesses
view app =
    { title =
        if app.data.isPublished then
            app.data.title
        else
            app.data.draftTitle
    , body = []
    }

-- Case on a FIELD of app.data (not app.data itself)
-- Tracks status field access + title/draftTitle in branches
view app =
    { title =
        case app.data.status of
            Published -> app.data.title
            Draft -> app.data.draftTitle
    , body = []
    }

-- Individual field accesses in list literals are tracked
-- (different from [app.data] which bails out)
view app =
    { title = String.join ", " [ app.data.title, app.data.subtitle ]
    , body = []
    }

-- Nested local function applications
-- outer receives the RESULT of extractTitle (a String), not app.data
-- So only the fields used by extractTitle are tracked
extractTitle data = data.title
view app =
    { title = String.toUpper (extractTitle app.data)  -- only 'title' is tracked
    , body = []
    }

-- This also works with parenthesized expressions
view app =
    { title = process (helper app.data)  -- tracks fields from helper
    , body = []
    }
helper data = data.title ++ data.subtitle
```

## Safe Fallback Patterns

These patterns cause ALL fields to remain persistent (no optimization, but safe):

| Pattern | Behavior | Implementation |
|---------|----------|----------------|
| `case app.data of MyConstructor x -> ...` (constructor) | Marks ALL persistent | Non-trackable pattern in `extractCasePatternFields` |
| `[app.data]` or `(app.data, x)` | Marks ALL persistent | `hasWrappedAppData` classification |
| `{ rec \| field = app.data }` | Marks ALL persistent | `MarkAllFieldsUsed` in extractFieldAccess |
| `Data` as constructor (`map4 Data`) | Skips transformation | `dataUsedAsConstructor` flag |
| Unknown helper: `someFunction app.data` | Marks ALL persistent | `AddUnknownHelper` action |
| Qualified helper: `Module.fn app.data` | Marks ALL persistent | `maybeFuncName = Nothing` |

Note: Case expressions with variable patterns (`case app.data of d -> d.title`) are now trackable - see Helper Function Analysis.

## Known Limitations

These patterns are intentionally not optimized (safe fallback behavior):

### 1. Cross-module helpers
```elm
-- Intentionally bails out
import MyHelpers exposing (render)
view app = render app.data
```
Can't analyze functions from other modules. Bails out correctly.

### 2. Higher-order function patterns
```elm
-- Bails out correctly (app.data wrapped in list)
view app =
    List.map (\d -> d.field) [app.data]
```

### 3. Helper functions that return functions
```elm
-- Complex higher-order patterns - bails out
makeRenderer field = \data -> data |> field
view app = makeRenderer .body app.data
```

## Test Suites

All tests run via `npm test` from project root:

- `generator/dead-code-review/tests/` - Client transform tests
- `generator/server-review/tests/` - Server transform tests
- `generator/persistent-marking-agreement-test/tests/` - Agreement tests (CRITICAL)

## Files

| File | Purpose |
|------|---------|
| `generator/dead-code-review/src/Pages/Review/StaticViewTransform.elm` | Client-side field analysis and type narrowing |
| `generator/server-review/src/Pages/Review/ServerDataTransform.elm` | Server-side ephemeral detection and conversion |
| `generator/shared/src/Pages/Review/PersistentFieldTracking.elm` | Shared analysis utilities for client/server agreement |
| `generator/persistent-marking-agreement-test/tests/PersistentFieldsAgreementTest.elm` | Ensures client/server agreement |

## Adding New Features

When adding new tracking patterns:

1. Add test cases FIRST (TDD approach)
2. Test both positive case (optimization works) AND negative case (safe fallback)
3. Add agreement test to ensure client/server stay in sync
4. Verify `npm test` passes before considering complete
