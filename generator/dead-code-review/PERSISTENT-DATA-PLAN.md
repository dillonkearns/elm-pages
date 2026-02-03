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
| Multi-parameter helpers: `formatTitle prefix data = ...` | ✅ Working | `analyzeParameter` + `appDataArgIndex` tracking |
| Case with record pattern: `case data of { title } -> title` | ✅ Working | `extractCasePatternFields` in `analyzeFieldAccessesWithAliases` |

### Inline Lambda Analysis

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `(\d -> d.title) app.data` | ✅ Working | `analyzeInlineLambda` in checkAppDataPassedToHelper |
| `app.data \|> (\d -> d.title)` | ✅ Working | `checkAppDataPassedToHelperViaPipe` |
| `(\d -> d.title) <\| app.data` | ✅ Working | Same as pipe handling |
| Record destructuring: `(\{ title } -> title) app.data` | ✅ Working | Pattern analysis in `analyzeInlineLambda` |

### RouteBuilder Integration

| Pattern | Status | Implementation |
|---------|--------|----------------|
| `head = \app -> [...]` lambdas | ✅ Working | Head function body tracking |
| Non-conventional names: `{ head = seoTags }` | ✅ Working | `routeBuilderHeadFn` extraction |
| Data function stubbing | ✅ Working | `dataFunctionBodyRange` tracking |

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

-- Multi-parameter helpers (data in any position)
formatTitle prefix data = prefix ++ data.title  -- data is second param
view app = formatTitle "Hello: " app.data  -- tracks title on second arg

-- Helper functions with case and record pattern (precise tracking)
-- The record pattern in case explicitly declares which fields are needed
extractTitle data =
    case data of
        { title } -> title
view app = extractTitle app.data  -- tracks only title as used

-- Inline lambdas (analyzed in place, no helper function needed)
view app = { title = (\d -> d.title) app.data, body = [] }

-- Inline lambdas with pipe operator
view app = { title = app.data |> (\d -> d.title), body = [] }

-- Inline lambdas with record destructuring
view app = { title = (\{ title } -> title) app.data, body = [] }

-- Let bindings
let title = app.data.title in ...

-- Record destructuring
let { title, body } = app.data in ...

-- RouteBuilder lambdas
head = \app -> [ title app.data.title ]
```

## Safe Fallback Patterns

These patterns cause ALL fields to remain persistent (no optimization, but safe):

| Pattern | Behavior | Implementation |
|---------|----------|----------------|
| `case app.data of d -> ...` (variable) | Marks ALL persistent | `extractCasePatternFields` → `UntrackablePattern` |
| `case app.data of { title } -> ...` (record) | Tracks fields ✅ | `TrackableFields` |
| `[app.data]` or `(app.data, x)` | Marks ALL persistent | `hasWrappedAppData` classification |
| `{ rec \| field = app.data }` | Marks ALL persistent | `MarkAllFieldsUsed` in extractFieldAccess |
| `Data` as constructor (`map4 Data`) | Skips transformation | `dataUsedAsConstructor` flag |
| Unknown helper: `someFunction app.data` | Marks ALL persistent | `AddUnknownHelper` action |
| Qualified helper: `Module.fn app.data` | Marks ALL persistent | `maybeFuncName = Nothing` |

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
