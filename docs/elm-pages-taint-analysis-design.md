# elm-pages Taint Analysis & Data Flow Tracking

## Overview

This document outlines an approach for implementing two related data flow analysis features in elm-pages:

1. **Tainted Value Detection** - Detecting when dynamic values (like `model`) flow into regions that should be static (like `View.freeze`)
2. **Persistent vs Ephemeral Data Classification** - Automatically determining which `Data` record fields are needed on the client vs. only used during server/build phases

Both features are forms of **taint analysis** - tracking how "interesting" values propagate through code.

---

## Reference: elm-review-unused Source Locations

This section provides direct references to the elm-review-unused codebase for implementation guidance.

### Core Types & Structures

| What | File | Lines | Description |
|------|------|-------|-------------|
| **Nonempty list (scope stack)** | [NonemptyList.elm](src/NoUnused/NonemptyList.elm) | 1-143 | Non-empty list for guaranteed scope stack |
| **Scope type (Variables)** | [Variables.elm](src/NoUnused/Variables.elm) | 200-204 | `{ declared, used, namesToIgnore }` |
| **Scope type (Patterns)** | [Patterns.elm](src/NoUnused/Patterns.elm) | 80-83 | Simpler `{ declared, used }` |
| **Scope type (Parameters)** | [Parameters.elm](src/NoUnused/Parameters.elm) | 223-231 | Extended with `usedRecursively`, `toReport` |
| **VariableInfo** | [Variables.elm](src/NoUnused/Variables.elm) | 207-212 | Metadata for declared variables |
| **ModuleContext** | [Variables.elm](src/NoUnused/Variables.elm) | 143-157 | Full module analysis context |
| **ProjectContext** | [Variables.elm](src/NoUnused/Variables.elm) | 137-140 | Cross-module state |
| **ParameterPath (nesting)** | [ParameterPath.elm](src/NoUnused/Parameters/ParameterPath.elm) | 23-40 | Tracks nested parameter paths |
| **NameVisitor** | [NameVisitor.elm](src/NoUnused/Patterns/NameVisitor.elm) | 1-476 | Generic visitor for all names |

### Key Functions

| What | File | Lines | Description |
|------|------|-------|-------------|
| **getDeclaredNamesFromPattern** | [Variables.elm](src/NoUnused/Variables.elm) | 1064-1099 | Extract names from patterns |
| **markAsUsed** | [Variables.elm](src/NoUnused/Variables.elm) | 1769-1784 | Mark a variable as used in scope |
| **registerVariable** | [Variables.elm](src/NoUnused/Variables.elm) | 1736-1747 | Add variable to current scope's `declared` |
| **makeReport** | [Variables.elm](src/NoUnused/Variables.elm) | 1826-1838 | Pop scope and report unused vars |
| **makeReportHelp** | [Variables.elm](src/NoUnused/Variables.elm) | 1841-1856 | Compute unused = declared - used |
| **scopeWithPatternsToIgnore** | [Variables.elm](src/NoUnused/Variables.elm) | 1640-1645 | Create scope with `namesToIgnore` |
| **markValuesFromPatternsAsUsed** | [Variables.elm](src/NoUnused/Variables.elm) | 1102-1136 | Mark pattern values as used |

### Visitor Patterns

| What | File | Lines | Description |
|------|------|-------|-------------|
| **moduleVisitor setup** | [Variables.elm](src/NoUnused/Variables.elm) | 120-134 | Full visitor chain setup |
| **Project rule setup** | [Variables.elm](src/NoUnused/Variables.elm) | 104-117 | `withContextFromImportedModules` |
| **fromProjectToModule** | [Variables.elm](src/NoUnused/Variables.elm) | 235-254 | Context creator pattern |
| **fromModuleToProject** | [Variables.elm](src/NoUnused/Variables.elm) | 257-270 | Export to project context |
| **foldProjectContexts** | [Variables.elm](src/NoUnused/Variables.elm) | 273-277 | Merge project contexts |
| **expressionEnterVisitor** | [Variables.elm](src/NoUnused/Variables.elm) | 779-849 | Scope push on let/lambda |
| **expressionExitVisitor** | [Variables.elm](src/NoUnused/Variables.elm) | 852-862 | Scope pop and report |
| **letDeclarationEnterVisitor** | [Variables.elm](src/NoUnused/Variables.elm) | 865-897 | Register let-bound functions |
| **caseBranchEnterVisitor** | [Variables.elm](src/NoUnused/Variables.elm) | 1014-1024 | Push scope for case patterns |
| **caseBranchExitVisitor** | [Variables.elm](src/NoUnused/Variables.elm) | 1027-1029 | Pop and report |

### Nonempty List API (to copy)

From [NonemptyList.elm](src/NoUnused/NonemptyList.elm):

| Function | Line | Usage |
|----------|------|-------|
| `type Nonempty a = Nonempty a (List a)` | 81-82 | Type definition |
| `fromElement : a -> Nonempty a` | 87-89 | Create singleton |
| `head : Nonempty a -> a` | 94-96 | Get current scope |
| `cons : a -> Nonempty a -> Nonempty a` | 101-103 | Push new scope |
| `pop : Nonempty a -> Nonempty a` | 116-123 | Pop scope (keeps at least one) |
| `mapHead : (a -> a) -> Nonempty a -> Nonempty a` | 140-142 | Update current scope |

---

## Design Constraints & Decisions

Based on elm-pages requirements:

| Question | Decision | Rationale |
|----------|----------|-----------|
| **Entry points** | Known elm-pages primitives only (RouteBuilder API) | elm-pages controls all entry points (`view`, `update`, etc.) via RouteBuilder |
| **When uncertain** | Assume tainted (conservative) | Over-tainting causes false positives (annoying but safe). Under-tainting causes silent bugs (unacceptable) |
| **Cross-module tracking** | Follow through user code, stop at package boundaries | Can analyze user's helper modules; external packages assume tainted |
| **Granularity goal** | As granular as possible within analyzable code | Only fall back to conservative when code is not visible |

### Known Entry Points (RouteBuilder API)

The taint sources are introduced through specific RouteBuilder patterns:

```elm
-- These are the known shapes where taint sources appear
RouteBuilder.single
    { data = ...
    , head = \data -> ...           -- data is NOT tainted (build-time)
    , view = \data model -> ...     -- model IS tainted, data is NOT
    }

RouteBuilder.preRender
    { data = ...
    , pages = ...
    , head = \data -> ...
    , view = \data model -> ...     -- model IS tainted
    }

-- Similar patterns for serverRender, etc.
```

---

## Part 1: Tainted Value Detection

### Goal

Detect and report errors when values derived from `model` (or other dynamic sources) are used inside `View.freeze` blocks, which are meant to contain only static, build-time-resolvable content.

### Examples

```elm
view : Data -> Model -> View Msg
view data model =
    let
        -- Tainted: derived from model
        userName = model.user.name

        -- Tainted: uses tainted value
        greeting = "Hello, " ++ userName

        -- Pure: only uses data (build-time available)
        title = data.pageTitle
    in
    div []
        [ View.freeze
            (\_ -> text greeting)   -- ERROR: greeting is tainted by model
        , View.freeze
            (\_ -> text title)      -- OK: title is pure
        ]
```

### Taint Propagation Rules

A value becomes **tainted** if:

| Rule | Example | Result |
|------|---------|--------|
| Direct reference to taint source | `model` | Tainted |
| Field access on tainted value | `model.user` | Tainted |
| Pattern destructuring tainted value | `let { user } = model` | `user` is tainted |
| Using tainted value in expression | `"Hi " ++ model.name` | Result is tainted |
| Function application with tainted arg | `String.toUpper model.name` | Result is tainted |
| Let binding using tainted value | `let x = model.foo in x` | `x` is tainted |
| Calling user function with tainted arg | `Helpers.format model.user` | Result is tainted (analyzed) |
| Calling package function with tainted arg | `Json.Encode.string model.name` | Result is tainted (conservative) |

### Taint Sources

For `View.freeze`, the primary taint source is:
- `model` parameter (and anything derived from it)

Optionally could also include:
- `msg` values (if applicable)
- Any `Cmd` or `Sub` producing values

### What Does NOT Propagate Taint

- Constants: `"hello"`, `42`, `True`
- Pure data transformations on pure values: `String.length data.title`
- Values from `Data` parameter (build-time available)
- Values from module-level constants
- Function calls where NO tainted values are passed as arguments

---

## Part 2: Persistent vs Ephemeral Data Classification

### Goal

Automatically classify which fields of the route's `Data` record are:
- **Ephemeral**: Only used in server/build phases (can be stripped from client payload)
- **Persistent**: Needed on the client (must be sent in `content.dat`)

### Classification Rules

A `Data` field is **persistent** if it is used in any of these contexts:
1. Inside a `view` function body (which has access to `Model`)
2. Inside code that handles `Msg` values
3. Passed to any function that could execute on the client

A `Data` field is **ephemeral** if:
1. Only used in `head : Data -> List Head.Tag`
2. Only used in build-time lifecycle functions
3. Only used to compute other ephemeral values

### Example

```elm
type alias Data =
    { pageTitle : String        -- Ephemeral: only in head
    , userName : String         -- Persistent: used in view
    , analyticsId : String      -- Ephemeral: only in head
    , userAvatar : String       -- Persistent: used in view
    }

head : Data -> List Head.Tag
head data =
    [ Head.title data.pageTitle
    , Head.meta [ ("analytics", data.analyticsId) ]
    ]

view : Data -> Model -> View Msg
view data model =
    div []
        [ img [ src data.userAvatar ] []
        , text data.userName
        ]
```

Result: `{ userName, userAvatar }` are persistent; `{ pageTitle, analyticsId }` are ephemeral.

---

## Part 3: Proposed Architecture

### Core Types

```elm
module DataFlow exposing (..)

-- What kind of value tracking are we doing?
type TaintSource
    = ModelTaint              -- From the Model parameter
    | EphemeralDataTaint      -- From Data, but only in ephemeral context
    | MsgTaint                -- From Msg values

-- The taint status of a binding
-- Compare to: Variables.elm:200-204 (Scope type uses Dict for declared/used)
-- Our version is simpler: we only track taint status, not removal ranges
type TaintStatus
    = Pure                    -- Definitely not tainted by any source
    | Tainted (Set TaintSource)  -- Tainted by these sources

-- Note: No "Unknown" status - when uncertain, we mark as Tainted (conservative)

-- Information about a function's taint behavior (for user-defined functions)
type alias FunctionTaintSignature =
    { -- Which parameter indices, if tainted, will taint the return value?
      -- For conservative analysis: if we can't determine, assume ALL params taint result
      paramsThatTaintResult : ParamTaintBehavior
    }

type ParamTaintBehavior
    = Analyzed (Set Int)      -- We analyzed this function, these params taint result
    | NotAnalyzable           -- External package or couldn't analyze - assume all taint

-- The main tracking context
-- Compare to: Variables.elm:143-157 (ModuleContext)
type alias TaintContext =
    { -- Current bindings and their taint status
      -- Compare to: Variables.elm:200 `declared : Dict String VariableInfo`
      -- We use TaintStatus instead of VariableInfo
      bindings : Nonempty (Dict String TaintStatus)

      -- Known function signatures from user's codebase (built during analysis)
    , userFunctionSignatures : Dict ( ModuleName, String ) FunctionTaintSignature

      -- Are we currently inside a "must be pure" region like View.freeze?
    , inPureRegion : Bool

      -- The taint sources we care about in this analysis
    , activeSources : Set TaintSource

      -- Current module name (for resolving local function calls)
    , currentModule : ModuleName

      -- Set of user modules (vs external packages)
    , userModules : Set ModuleName
    }
```

### Scope Stack (from elm-review-unused)

Use the `Nonempty` pattern from [NonemptyList.elm](src/NoUnused/NonemptyList.elm):

```elm
-- Copy from NonemptyList.elm:81-82
type Nonempty a
    = Nonempty a (List a)

-- Push new scope on let/lambda/case entry
-- See: Variables.elm:821, 845, 895 for usage patterns
pushScope : TaintContext -> TaintContext
pushScope ctx =
    { ctx | bindings = cons Dict.empty ctx.bindings }

-- Pop scope on exit
-- See: Variables.elm:1834 (in makeReport)
popScope : TaintContext -> TaintContext
popScope ctx =
    { ctx | bindings = pop ctx.bindings }

-- Add a binding to current scope
-- Compare to: Variables.elm:1736-1747 (registerVariable)
addBinding : String -> TaintStatus -> TaintContext -> TaintContext
addBinding name status ctx =
    { ctx | bindings = mapHead (Dict.insert name status) ctx.bindings }

-- Look up a binding (searches all scopes, innermost first)
lookupBinding : String -> TaintContext -> TaintStatus
lookupBinding name ctx =
    lookupInScopes name (toList ctx.bindings)
        |> Maybe.withDefault Pure  -- If not found, it's a top-level or imported value
```

### Pattern Extraction (from elm-review-unused)

Adapt from [Variables.elm:1064-1099](src/NoUnused/Variables.elm#L1064-L1099):

```elm
-- Original extracts Set String, we extract List (String, TaintStatus)
-- to propagate taint from the matched expression to bound names
extractBindingsFromPattern : TaintStatus -> Node Pattern -> List ( String, TaintStatus )
extractBindingsFromPattern parentTaint node =
    case Node.value node of
        -- Compare to Variables.elm:1072-1073
        Pattern.VarPattern name ->
            [ ( name, parentTaint ) ]

        -- Compare to Variables.elm:1078-1081
        Pattern.RecordPattern fields ->
            -- Each field inherits parent taint
            List.map (\f -> ( Node.value f, parentTaint )) fields

        -- Compare to Variables.elm:1075-1076
        Pattern.AsPattern pattern (Node _ asName) ->
            ( asName, parentTaint ) :: extractBindingsFromPattern parentTaint pattern

        -- Compare to Variables.elm:1083-1084
        Pattern.TuplePattern patterns ->
            List.concatMap (extractBindingsFromPattern parentTaint) patterns

        -- Compare to Variables.elm:1086-1087
        Pattern.NamedPattern _ patterns ->
            List.concatMap (extractBindingsFromPattern parentTaint) patterns

        -- Compare to Variables.elm:1089-1090
        Pattern.UnConsPattern head tail ->
            extractBindingsFromPattern parentTaint head
                ++ extractBindingsFromPattern parentTaint tail

        -- Compare to Variables.elm:1092-1093
        Pattern.ListPattern patterns ->
            List.concatMap (extractBindingsFromPattern parentTaint) patterns

        -- Compare to Variables.elm:1069-1070
        Pattern.ParenthesizedPattern pattern ->
            extractBindingsFromPattern parentTaint pattern

        _ ->
            []
```

### Expression Taint Analysis

```elm
-- Compute the taint status of an expression
analyzeTaint : TaintContext -> Node Expression -> TaintStatus
analyzeTaint ctx node =
    case Node.value node of
        -- Literals are always pure
        Expression.Integer _ -> Pure
        Expression.Floatable _ -> Pure
        Expression.Literal _ -> Pure
        Expression.CharLiteral _ -> Pure
        Expression.UnitExpr -> Pure

        -- Variable reference: look up in bindings
        -- Compare to: Variables.elm:795-800 (markValueAsUsed for local names)
        Expression.FunctionOrValue [] name ->
            lookupBinding name ctx

        -- Qualified reference: check if it's a user module we've analyzed
        Expression.FunctionOrValue moduleName name ->
            -- Module-level values from packages are pure unless called with tainted args
            -- (the taint comes from application, not the reference itself)
            Pure

        -- Field access propagates taint
        Expression.RecordAccess expr _ ->
            analyzeTaint ctx expr

        -- Record access function (.field) is pure until applied
        Expression.RecordAccessFunction _ ->
            Pure

        -- Function application: the key complexity
        Expression.Application (fn :: args) ->
            analyzeApplication ctx fn args

        -- Let expression: handled by visitor (bindings added to context)
        Expression.LetExpression { expression } ->
            -- The let body's taint is computed with bindings already in context
            analyzeTaint ctx expression

        -- If expression: union of branch taints (conservative)
        Expression.IfBlock cond thenBranch elseBranch ->
            unionTaint
                [ analyzeTaint ctx cond
                , analyzeTaint ctx thenBranch
                , analyzeTaint ctx elseBranch
                ]

        -- Case expression: union of scrutinee and all branch taints
        Expression.CaseExpression { expression, cases } ->
            let
                exprTaint = analyzeTaint ctx expression
                -- Branch analysis is handled by visitor (pattern bindings added to context)
                -- Here we just note that if scrutinee is tainted, result could be
            in
            exprTaint  -- Simplified; full impl uses visitor pattern

        -- Operators: both operands contribute
        Expression.OperatorApplication _ _ left right ->
            unionTaint [ analyzeTaint ctx left, analyzeTaint ctx right ]

        -- Negation
        Expression.Negation expr ->
            analyzeTaint ctx expr

        -- Tuples, lists, records: union of element taints
        Expression.TupledExpression exprs ->
            unionTaint (List.map (analyzeTaint ctx) exprs)

        Expression.ListExpr exprs ->
            unionTaint (List.map (analyzeTaint ctx) exprs)

        Expression.RecordExpr fields ->
            unionTaint (List.map (\(Node _ (_, expr)) -> analyzeTaint ctx expr) fields)

        Expression.RecordUpdateExpression (Node _ recordName) fields ->
            -- Record update: union of original record taint and field taints
            unionTaint
                (lookupBinding recordName ctx
                    :: List.map (\(Node _ (_, expr)) -> analyzeTaint ctx expr) fields
                )

        -- Lambda: the lambda itself is pure; taint comes from application
        Expression.LambdaExpression _ ->
            Pure

        -- Parentheses
        Expression.ParenthesizedExpression expr ->
            analyzeTaint ctx expr

        -- GLSLExpression (rare)
        Expression.GLSLExpression _ ->
            Pure

        -- Hex/binary literals
        Expression.Hex _ ->
            Pure

        -- Operator as function
        Expression.PrefixOperator _ ->
            Pure

        Expression.Operator _ ->
            Pure


-- Combine multiple taint statuses (conservative: any taint wins)
unionTaint : List TaintStatus -> TaintStatus
unionTaint statuses =
    List.foldl mergeTaint Pure statuses


mergeTaint : TaintStatus -> TaintStatus -> TaintStatus
mergeTaint a b =
    case ( a, b ) of
        ( Pure, x ) -> x
        ( x, Pure ) -> x
        ( Tainted s1, Tainted s2 ) -> Tainted (Set.union s1 s2)
```

### Function Application Analysis

This is the core of cross-module taint tracking:

```elm
analyzeApplication : TaintContext -> Node Expression -> List (Node Expression) -> TaintStatus
analyzeApplication ctx fnNode args =
    let
        -- First, compute taint of each argument
        argTaints : List TaintStatus
        argTaints = List.map (analyzeTaint ctx) args

        -- Are ANY arguments tainted?
        anyArgTainted : Bool
        anyArgTainted = List.any (\t -> t /= Pure) argTaints

        -- Collect all taint sources from arguments
        allArgTaintSources : Set TaintSource
        allArgTaintSources =
            argTaints
                |> List.filterMap (\t -> case t of
                    Tainted sources -> Just sources
                    Pure -> Nothing
                )
                |> List.foldl Set.union Set.empty
    in
    -- If no args are tainted, result is pure (regardless of function)
    if not anyArgTainted then
        Pure
    else
        -- Some arg is tainted - need to check the function
        case Node.value fnNode of
            Expression.FunctionOrValue moduleName name ->
                analyzeNamedFunctionCall ctx moduleName name argTaints allArgTaintSources

            Expression.RecordAccessFunction _ ->
                -- (.field) applied to tainted record = tainted result
                Tainted allArgTaintSources

            Expression.ParenthesizedExpression inner ->
                -- Unwrap and recurse
                analyzeApplication ctx inner args

            Expression.LambdaExpression _ ->
                -- Lambda applied inline - conservative: if any arg tainted, result tainted
                Tainted allArgTaintSources

            _ ->
                -- Dynamic function call - conservative
                Tainted allArgTaintSources


analyzeNamedFunctionCall :
    TaintContext
    -> ModuleName
    -> String
    -> List TaintStatus
    -> Set TaintSource
    -> TaintStatus
analyzeNamedFunctionCall ctx moduleName name argTaints allArgTaintSources =
    let
        qualifiedName = ( moduleName, name )
    in
    case Dict.get qualifiedName ctx.userFunctionSignatures of
        Just signature ->
            -- We have analyzed this function
            case signature.paramsThatTaintResult of
                Analyzed taintingParams ->
                    -- Check if any of the tainting params received tainted args
                    let
                        taintedArgIndices =
                            argTaints
                                |> List.indexedMap (\i t -> ( i, t ))
                                |> List.filter (\( _, t ) -> t /= Pure)
                                |> List.map Tuple.first
                                |> Set.fromList

                        relevantTaintedParams =
                            Set.intersect taintedArgIndices taintingParams
                    in
                    if Set.isEmpty relevantTaintedParams then
                        Pure
                    else
                        -- Collect taint sources from relevant args only
                        argTaints
                            |> List.indexedMap (\i t -> ( i, t ))
                            |> List.filter (\( i, _ ) -> Set.member i relevantTaintedParams)
                            |> List.filterMap (\( _, t ) -> case t of
                                Tainted s -> Just s
                                Pure -> Nothing
                            )
                            |> List.foldl Set.union Set.empty
                            |> Tainted

                NotAnalyzable ->
                    -- Couldn't analyze - conservative
                    Tainted allArgTaintSources

        Nothing ->
            -- Not in our signatures - is it a user module or external?
            if isUserModule ctx moduleName then
                -- User module we haven't analyzed yet
                -- This shouldn't happen if we analyze in dependency order
                -- Conservative fallback
                Tainted allArgTaintSources
            else
                -- External package - conservative: tainted args = tainted result
                Tainted allArgTaintSources


-- Check if a module is part of the user's codebase (vs external package)
isUserModule : TaintContext -> ModuleName -> Bool
isUserModule ctx moduleName =
    Set.member moduleName ctx.userModules
```

---

## Part 4: Cross-Module Analysis Strategy

### Two-Pass Approach

Since we need to analyze user functions before we can track taint through calls to them:

**Pass 1: Build Function Signatures**
- Analyze each module in the user's codebase
- For each function, determine which parameters can taint the return value
- Build a `Dict (ModuleName, String) FunctionTaintSignature`

**Pass 2: Taint Detection**
- Use the collected signatures to analyze taint flow
- Report errors for tainted values in pure regions

### Inferring Function Taint Signatures

```elm
-- For a function definition, determine which params taint the result
inferFunctionSignature : TaintContext -> Node Function -> ( String, FunctionTaintSignature )
inferFunctionSignature ctx fn =
    let
        impl = Node.value (Node.value fn).declaration
        name = Node.value impl.name
        params = impl.arguments
        body = impl.expression

        -- Create a context where each param has a unique taint marker
        paramContexts : List ( Int, String, TaintStatus )
        paramContexts =
            params
                |> List.indexedMap (\i pattern ->
                    extractBindingsFromPattern
                        (Tainted (Set.singleton (ParamMarker i)))
                        pattern
                        |> List.map (\( n, t ) -> ( i, n, t ))
                )
                |> List.concat

        -- Build context with param bindings
        analysisCtx =
            List.foldl
                (\( _, n, t ) c -> addBinding n t c)
                (pushScope ctx)
                paramContexts

        -- Analyze the body
        bodyTaint = analyzeTaint analysisCtx body
    in
    ( name
    , { paramsThatTaintResult =
            case bodyTaint of
                Tainted sources ->
                    sources
                        |> Set.toList
                        |> List.filterMap (\s ->
                            case s of
                                ParamMarker i -> Just i
                                _ -> Nothing
                        )
                        |> Set.fromList
                        |> Analyzed

                Pure ->
                    Analyzed Set.empty
      }
    )


-- Special taint source for tracking which param taints result
type TaintSource
    = ModelTaint
    | EphemeralDataTaint
    | MsgTaint
    | ParamMarker Int  -- Internal: tracks which param flows to result
```

### Module Analysis Order

To analyze functions before they're called, process modules in dependency order.

Compare to [Variables.elm:104-117](src/NoUnused/Variables.elm#L104-L117) for project rule setup:

```elm
-- Project rule that processes modules in order
-- Key: Rule.withContextFromImportedModules (line 115) gives us analyzed modules' context
rule : Rule
rule =
    Rule.newProjectRuleSchema "TaintAnalysis" initialProjectContext
        |> Rule.withDependenciesProjectVisitor dependenciesVisitor
        |> Rule.withModuleVisitor moduleVisitor
        |> Rule.withModuleContextUsingContextCreator
            { fromProjectToModule = fromProjectToModule
            , fromModuleToProject = fromModuleToProject
            , foldProjectContexts = foldProjectContexts
            }
        |> Rule.withContextFromImportedModules  -- Key: gives us analyzed modules' context
        |> Rule.withFinalProjectEvaluation finalEvaluation
        |> Rule.fromProjectRuleSchema


type alias ProjectContext =
    { -- Accumulated function signatures from all analyzed modules
      functionSignatures : Dict ( ModuleName, String ) FunctionTaintSignature

      -- Set of modules in user's codebase (vs packages)
    , userModules : Set ModuleName

      -- Detected errors across all modules
    , errors : List (Error { useErrorForModule : () })
    }


-- Compare to: Variables.elm:257-270
fromModuleToProject : Rule.ContextCreator ModuleContext ProjectContext
fromModuleToProject =
    Rule.initContextCreator
        (\moduleName moduleCtx ->
            { functionSignatures =
                moduleCtx.inferredSignatures
                    |> List.map (\( name, sig ) -> ( ( moduleName, name ), sig ))
                    |> Dict.fromList
            , userModules = Set.singleton moduleName
            , errors = moduleCtx.errors
            }
        )
        |> Rule.withModuleName


-- Compare to: Variables.elm:235-254
fromProjectToModule : Rule.ContextCreator ProjectContext ModuleContext
fromProjectToModule =
    Rule.initContextCreator
        (\projectCtx ->
            { taintContext =
                { bindings = NonemptyList.fromElement Dict.empty
                , userFunctionSignatures = projectCtx.functionSignatures
                , inPureRegion = False
                , activeSources = Set.fromList [ ModelTaint ]
                , userModules = projectCtx.userModules
                }
            , inferredSignatures = []
            , errors = []
            }
        )


-- Compare to: Variables.elm:273-277
foldProjectContexts : ProjectContext -> ProjectContext -> ProjectContext
foldProjectContexts a b =
    { functionSignatures = Dict.union a.functionSignatures b.functionSignatures
    , userModules = Set.union a.userModules b.userModules
    , errors = a.errors ++ b.errors
    }
```

---

## Part 5: Entry Point Detection (RouteBuilder)

### Detecting Route Modules

```elm
-- Check if this module uses RouteBuilder and extract the view/head/etc functions
detectRouteBuilderUsage : Node Declaration -> Maybe RouteBuilderInfo
detectRouteBuilderUsage decl =
    case Node.value decl of
        Declaration.FunctionDeclaration fn ->
            let
                body = (Node.value fn).declaration |> Node.value |> .expression
            in
            case findRouteBuilderCall body of
                Just config ->
                    Just (extractRouteInfo config)
                Nothing ->
                    Nothing
        _ ->
            Nothing


type alias RouteBuilderInfo =
    { viewFunction : Maybe String      -- Name of the view function
    , headFunction : Maybe String      -- Name of the head function
    , dataType : Maybe TypeAnnotation  -- The Data type if we can find it
    }


-- Look for RouteBuilder.single, RouteBuilder.preRender, etc.
findRouteBuilderCall : Node Expression -> Maybe (Node Expression)
findRouteBuilderCall expr =
    case Node.value expr of
        Expression.Application ((Node _ (Expression.FunctionOrValue [ "RouteBuilder" ] builderFn)) :: args) ->
            if List.member builderFn [ "single", "preRender", "serverRender" ] then
                List.head args  -- The config record
            else
                Nothing

        Expression.OperatorApplication "|>" _ left right ->
            -- Check both sides for piping
            findRouteBuilderCall left
                |> Maybe.orElse (findRouteBuilderCall right)

        _ ->
            Nothing
```

### Setting Up Taint Context for View Functions

```elm
-- When we enter a view function identified by RouteBuilder
setupViewContext : TaintContext -> List (Node Pattern) -> TaintContext
setupViewContext ctx params =
    case params of
        [ dataParam, modelParam ] ->
            let
                -- data parameter is pure
                dataBindings = extractBindingsFromPattern Pure dataParam

                -- model parameter is tainted
                modelBindings = extractBindingsFromPattern (Tainted (Set.singleton ModelTaint)) modelParam
            in
            ctx
                |> pushScope
                |> addBindings dataBindings
                |> addBindings modelBindings

        _ ->
            -- Unexpected signature, be conservative
            ctx
```

---

## Part 6: Visitor Pattern Implementation

### Module Visitor Setup

Compare to [Variables.elm:120-134](src/NoUnused/Variables.elm#L120-L134):

```elm
moduleVisitor :
    Rule.ModuleRuleSchema schemaState ModuleContext
    -> Rule.ModuleRuleSchema { schemaState | hasAtLeastOneVisitor : () } ModuleContext
moduleVisitor schema =
    schema
        |> Rule.withDeclarationListVisitor declarationListVisitor
        |> Rule.withDeclarationEnterVisitor declarationEnterVisitor
        |> Rule.withDeclarationExitVisitor declarationExitVisitor
        |> Rule.withExpressionEnterVisitor expressionEnterVisitor
        |> Rule.withExpressionExitVisitor expressionExitVisitor
        |> Rule.withLetDeclarationEnterVisitor letDeclarationEnterVisitor
        -- Compare to: Variables.elm:132-133
        |> Rule.withCaseBranchEnterVisitor caseBranchEnterVisitor
        |> Rule.withCaseBranchExitVisitor caseBranchExitVisitor
```

### Declaration Visitors

```elm
declarationListVisitor : List (Node Declaration) -> ModuleContext -> ( List (Error {}), ModuleContext )
declarationListVisitor declarations ctx =
    -- First pass: infer signatures for all top-level functions
    let
        signatures =
            declarations
                |> List.filterMap (\decl ->
                    case Node.value decl of
                        Declaration.FunctionDeclaration fn ->
                            Just (inferFunctionSignature ctx.taintContext fn)
                        _ ->
                            Nothing
                )
    in
    ( [], { ctx | inferredSignatures = signatures } )


declarationEnterVisitor : Node Declaration -> ModuleContext -> ( List (Error {}), ModuleContext )
declarationEnterVisitor node ctx =
    case Node.value node of
        Declaration.FunctionDeclaration fn ->
            let
                impl = Node.value (Node.value fn).declaration
                name = Node.value impl.name
            in
            if isViewFunction name ctx then
                -- This is a view function - set up taint tracking
                ( [], { ctx | taintContext = setupViewContext ctx.taintContext impl.arguments } )
            else
                -- Regular function - just push scope for params
                let
                    paramBindings =
                        impl.arguments
                            |> List.concatMap (extractBindingsFromPattern Pure)
                in
                ( [], { ctx | taintContext = pushScope ctx.taintContext |> addBindings paramBindings } )

        _ ->
            ( [], ctx )


declarationExitVisitor : Node Declaration -> ModuleContext -> ( List (Error {}), ModuleContext )
declarationExitVisitor node ctx =
    case Node.value node of
        Declaration.FunctionDeclaration _ ->
            ( [], { ctx | taintContext = popScope ctx.taintContext } )

        _ ->
            ( [], ctx )
```

### Expression Visitors

Compare to [Variables.elm:779-862](src/NoUnused/Variables.elm#L779-L862):

```elm
expressionEnterVisitor : Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
expressionEnterVisitor node ctx =
    case Node.value node of
        -- Entering View.freeze: mark as pure region
        Expression.Application ((Node _ (Expression.FunctionOrValue [ "View" ] "freeze")) :: _) ->
            ( [], { ctx | taintContext = enterPureRegion ctx.taintContext } )

        -- Let expression: push new scope
        -- Compare to: Variables.elm:828-846
        Expression.LetExpression _ ->
            ( [], { ctx | taintContext = pushScope ctx.taintContext } )

        -- Lambda: push scope and add param bindings
        -- Compare to: Variables.elm:819-821
        -- Lambda params shadow outer bindings, so they're pure within the lambda
        Expression.LambdaExpression { args } ->
            let
                bindings = List.concatMap (extractBindingsFromPattern Pure) args
                newCtx = ctx.taintContext |> pushScope |> addBindings bindings
            in
            ( [], { ctx | taintContext = newCtx } )

        -- Check for tainted references in pure regions
        Expression.FunctionOrValue [] name ->
            if ctx.taintContext.inPureRegion then
                case lookupBinding name ctx.taintContext of
                    Tainted sources ->
                        if Set.member ModelTaint sources then
                            ( [ taintError node name ], ctx )
                        else
                            ( [], ctx )
                    Pure ->
                        ( [], ctx )
            else
                ( [], ctx )

        _ ->
            ( [], ctx )


-- Compare to: Variables.elm:852-862
expressionExitVisitor : Node Expression -> ModuleContext -> ( List (Error {}), ModuleContext )
expressionExitVisitor node ctx =
    case Node.value node of
        Expression.Application ((Node _ (Expression.FunctionOrValue [ "View" ] "freeze")) :: _) ->
            ( [], { ctx | taintContext = exitPureRegion ctx.taintContext } )

        Expression.LetExpression _ ->
            ( [], { ctx | taintContext = popScope ctx.taintContext } )

        Expression.LambdaExpression _ ->
            ( [], { ctx | taintContext = popScope ctx.taintContext } )

        _ ->
            ( [], ctx )


-- Error creation
taintError : Node Expression -> String -> Error {}
taintError node name =
    Rule.error
        { message = "`" ++ name ++ "` cannot be used inside View.freeze"
        , details =
            [ "View.freeze creates static HTML at build time, but `" ++ name ++ "` depends on runtime data (model)."
            , "Either move this value outside of View.freeze, or use build-time data instead."
            ]
        }
        (Node.range node)
```

### Let Declaration Visitor

Compare to [Variables.elm:865-897](src/NoUnused/Variables.elm#L865-L897):

```elm
letDeclarationEnterVisitor :
    Node Expression.LetBlock
    -> Node Expression.LetDeclaration
    -> ModuleContext
    -> ( List (Error {}), ModuleContext )
letDeclarationEnterVisitor _ decl ctx =
    case Node.value decl of
        -- Compare to: Variables.elm:877-897
        Expression.LetFunction fn ->
            let
                impl = Node.value (Node.value fn).declaration
                name = Node.value impl.name
                params = impl.arguments
                body = impl.expression

                -- For let-bound functions, analyze the body to get taint
                -- Params are bound as pure within the function
                -- Compare to: Variables.elm:883-885 (getDeclaredNamesFromPattern)
                paramBindings =
                    params |> List.concatMap (extractBindingsFromPattern Pure)

                innerCtx =
                    ctx.taintContext |> pushScope |> addBindings paramBindings

                bodyTaint = analyzeTaint innerCtx body
            in
            -- The function name gets the body's taint
            ( [], { ctx | taintContext = addBinding name bodyTaint ctx.taintContext } )

        Expression.LetDestructuring pattern expr ->
            let
                exprTaint = analyzeTaint ctx.taintContext expr
                bindings = extractBindingsFromPattern exprTaint pattern
            in
            ( [], { ctx | taintContext = addBindings bindings ctx.taintContext } )
```

### Case Branch Visitor

Compare to [Variables.elm:1014-1029](src/NoUnused/Variables.elm#L1014-L1029):

```elm
-- Compare to: Variables.elm:1014-1024
caseBranchEnterVisitor :
    Node Expression.CaseBlock
    -> ( Node Pattern, Node Expression )
    -> ModuleContext
    -> ( List (Error {}), ModuleContext )
caseBranchEnterVisitor caseBlock ( pattern, _ ) ctx =
    let
        -- The scrutinee's taint propagates to pattern bindings
        scrutineeTaint = analyzeTaint ctx.taintContext (Node.value caseBlock).expression
        bindings = extractBindingsFromPattern scrutineeTaint pattern
        newCtx = ctx.taintContext |> pushScope |> addBindings bindings
    in
    ( [], { ctx | taintContext = newCtx } )


-- Compare to: Variables.elm:1027-1029
caseBranchExitVisitor :
    Node Expression.CaseBlock
    -> ( Node Pattern, Node Expression )
    -> ModuleContext
    -> ( List (Error {}), ModuleContext )
caseBranchExitVisitor _ _ ctx =
    ( [], { ctx | taintContext = popScope ctx.taintContext } )
```

---

## Part 7: Persistent/Ephemeral Data Analysis

### Tracking Data Field Access

```elm
type DataFieldContext
    = InHeadFunction         -- Definitely ephemeral context
    | InViewFunction         -- Definitely persistent context
    | InOtherFunction        -- Need to track callers


type alias DataFieldUsage =
    { field : String
    , usages : List DataFieldContext
    }


-- Track when we see data.fieldName
trackDataFieldAccess :
    String
    -> DataFieldContext
    -> ModuleContext
    -> ModuleContext
trackDataFieldAccess fieldName context ctx =
    { ctx
        | dataFieldUsages =
            Dict.update fieldName
                (\maybeUsage ->
                    Just
                        { field = fieldName
                        , usages =
                            context :: (maybeUsage |> Maybe.map .usages |> Maybe.withDefault [])
                        }
                )
                ctx.dataFieldUsages
    }


-- Detect data.field access
detectDataFieldAccess : TaintContext -> Node Expression -> Maybe String
detectDataFieldAccess ctx node =
    case Node.value node of
        Expression.RecordAccess recordExpr (Node _ fieldName) ->
            case Node.value recordExpr of
                Expression.FunctionOrValue [] recordName ->
                    -- Check if this is the "data" parameter
                    if isDataParameter recordName ctx then
                        Just fieldName
                    else
                        Nothing
                _ ->
                    Nothing
        _ ->
            Nothing
```

### Determining Persistence

```elm
-- A field is persistent if used in ANY persistent context
isPersistent : DataFieldUsage -> Bool
isPersistent usage =
    List.any ((==) InViewFunction) usage.usages


-- Get all persistent fields
getPersistentFields : Dict String DataFieldUsage -> Set String
getPersistentFields usages =
    usages
        |> Dict.values
        |> List.filter isPersistent
        |> List.map .field
        |> Set.fromList


-- Get all ephemeral fields
getEphemeralFields : Dict String DataFieldUsage -> Set String
getEphemeralFields usages =
    let
        allFields = Dict.keys usages |> Set.fromList
        persistent = getPersistentFields usages
    in
    Set.diff allFields persistent
```

---

## Part 8: Integration with elm-pages Codemod

### Analysis Output

```elm
type alias AnalysisResults =
    { -- Errors to report (taint violations)
      taintErrors : List TaintError

      -- Data field classification
    , ephemeralFields : Set String
    , persistentFields : Set String

      -- Function signatures (for potential future use)
    , functionSignatures : Dict ( ModuleName, String ) FunctionTaintSignature
    }


type alias TaintError =
    { moduleName : ModuleName
    , range : Range
    , variableName : String
    , taintSource : TaintSource
    }
```

### Codemod Transformation

Using the analysis results:

```elm
-- Original route module
type alias Data =
    { pageTitle : String    -- ephemeral
    , userName : String     -- persistent
    , analyticsId : String  -- ephemeral
    }

-- After codemod (for client bundle)
type alias Data =
    { userName : String
    }

-- The codemod also needs to:
-- 1. Update any pattern matches on Data
-- 2. Remove references to ephemeral fields
-- 3. Update the decoder/encoder for Data
```

---

## Part 9: Implementation Roadmap

### Phase 1: Basic Taint Detection (MVP)

**Goal**: Detect direct `model` usage in `View.freeze`

**Files to reference**:
- [NonemptyList.elm](src/NoUnused/NonemptyList.elm) - copy entire file
- [Variables.elm:200-204](src/NoUnused/Variables.elm#L200-L204) - Scope type pattern
- [Variables.elm:1064-1099](src/NoUnused/Variables.elm#L1064-L1099) - getDeclaredNamesFromPattern

**Steps**:
1. Implement scope stack (copy `Nonempty` from elm-review-unused)
2. Detect `view` functions via RouteBuilder pattern matching
3. Track `model` parameter as tainted
4. Push/pop scopes for let/lambda/case
5. Track let bindings and their taint (single-level)
6. Report errors for tainted references in `View.freeze`

**Handles**:
```elm
view data model =
    View.freeze (\_ -> text model.name)  -- ERROR

view data model =
    let userName = model.name in
    View.freeze (\_ -> text userName)    -- ERROR
```

### Phase 2: Deep Intra-Module Taint

**Goal**: Track taint through all local transformations

**Files to reference**:
- [Variables.elm:779-862](src/NoUnused/Variables.elm#L779-L862) - expression visitors
- [Variables.elm:1014-1029](src/NoUnused/Variables.elm#L1014-L1029) - case branch visitors

**Steps**:
1. Handle all expression types (if/case/operators/etc.)
2. Track taint through pattern matching in case expressions
3. Track taint through record updates
4. Handle partial application correctly

**Handles**:
```elm
view data model =
    let
        user = model.user
        { name } = user
        greeting = "Hello, " ++ name
    in
    View.freeze (\_ -> text greeting)    -- ERROR: greeting <- name <- user <- model
```

### Phase 3: Cross-Module Analysis

**Goal**: Track taint through calls to user's helper modules

**Files to reference**:
- [Variables.elm:104-117](src/NoUnused/Variables.elm#L104-L117) - project rule setup with `withContextFromImportedModules`
- [Variables.elm:235-277](src/NoUnused/Variables.elm#L235-L277) - context creators

**Steps**:
1. Implement two-pass analysis (signature inference, then taint detection)
2. Build function signature database during first pass
3. Use signatures to track taint through function calls
4. Handle module dependency ordering

**Handles**:
```elm
-- Helpers.elm
formatUser : User -> String
formatUser user = user.name ++ " (" ++ user.email ++ ")"

-- Route.elm
view data model =
    View.freeze (\_ -> text (Helpers.formatUser model.user))  -- ERROR
```

### Phase 4: Persistent/Ephemeral Classification

**Goal**: Automatically classify Data fields

1. Track Data field access with context (head vs view)
2. Classify fields based on usage patterns
3. Export classification for codemod use

### Phase 5: Codemod Integration

**Goal**: Use analysis to transform code

1. Generate stripped Data type for client
2. Update pattern matches and field accesses
3. Integrate with existing elm-pages build pipeline

---

## Appendix A: Code to Copy from elm-review-unused

### Nonempty List

Copy [NonemptyList.elm](src/NoUnused/NonemptyList.elm) in its entirety (lines 1-143).

```elm
module Nonempty exposing (Nonempty(..), fromElement, head, cons, pop, mapHead)

type Nonempty a = Nonempty a (List a)

fromElement : a -> Nonempty a
fromElement x = Nonempty x []

head : Nonempty a -> a
head (Nonempty x _) = x

cons : a -> Nonempty a -> Nonempty a
cons y (Nonempty x xs) = Nonempty y (x :: xs)

pop : Nonempty a -> Nonempty a
pop ((Nonempty _ xs) as original) =
    case xs of
        [] -> original
        y :: ys -> Nonempty y ys

mapHead : (a -> a) -> Nonempty a -> Nonempty a
mapHead fn (Nonempty x xs) = Nonempty (fn x) xs
```

### Pattern Name Extraction

Adapt from [Variables.elm:1064-1099](src/NoUnused/Variables.elm#L1064-L1099).

### Scope Operations

Reference patterns from:
- [Variables.elm:1736-1747](src/NoUnused/Variables.elm#L1736-L1747) - registerVariable (adding to scope)
- [Variables.elm:1769-1784](src/NoUnused/Variables.elm#L1769-L1784) - markAsUsed (updating scope)
- [Variables.elm:1826-1838](src/NoUnused/Variables.elm#L1826-L1838) - makeReport (pop and check)

---

## Appendix B: Edge Cases & Considerations

### Lambda Parameters in View.freeze

```elm
View.freeze
    (\staticData ->
        -- staticData is passed by elm-pages, should it be tainted?
        text staticData.something
    )
```

**Decision**: The lambda parameter in `View.freeze` is provided by elm-pages and should be pure. Only outer scope bindings can be tainted.

### Partial Application

```elm
view data model =
    let
        formatter = String.append model.prefix
    in
    View.freeze (\_ -> text (formatter "suffix"))  -- ERROR?
```

**Decision**: Yes, error. `formatter` captures `model.prefix`, so it's tainted.

### Record Update on Model

```elm
view data model =
    View.freeze (\_ ->
        text (toString { model | count = 0 })  -- ERROR
    )
```

**Decision**: Error. Record update on tainted value produces tainted value.

### Type Constructors

```elm
view data model =
    View.freeze (\_ ->
        case Just model.value of  -- ERROR
            Just x -> text (toString x)
            Nothing -> text "none"
    )
```

**Decision**: Error. `Just model.value` is tainted because it contains tainted data.

### Functions That Ignore Arguments

```elm
always : a -> b -> a
always x _ = x

view data model =
    View.freeze (\_ ->
        text (always "static" model)  -- Should this be OK?
    )
```

**Decision**: This is where signature analysis helps. If we analyze `always`, we see param 0 taints result but param 1 doesn't. So this would be OK.

For external packages, we're conservative, so `SomePackage.always "static" model` would be flagged as error (safe but potentially annoying).

---

## Appendix C: Testing Strategy

### Unit Tests for Taint Analysis

```elm
-- Test: Direct model reference
testDirectModelReference =
    """
    view data model =
        View.freeze (\\_ -> text model.name)
    """
    |> expectError "model.name"


-- Test: Taint through let binding
testLetBindingTaint =
    """
    view data model =
        let name = model.name in
        View.freeze (\\_ -> text name)
    """
    |> expectError "name"


-- Test: Shadowing allows usage
testShadowing =
    """
    view data model =
        View.freeze (\\_ ->
            let model = { name = "static" } in
            text model.name
        )
    """
    |> expectNoErrors


-- Test: Pure data is allowed
testPureData =
    """
    view data model =
        View.freeze (\\_ -> text data.title)
    """
    |> expectNoErrors
```

### Integration Tests

Test against real elm-pages route modules to ensure:
1. No false positives on valid code
2. All taint paths are caught
3. Error messages are helpful

---

## Appendix D: Quick Reference - Key Line Numbers

| Pattern | File | Lines |
|---------|------|-------|
| Nonempty type | NonemptyList.elm | 81-82 |
| Scope type | Variables.elm | 200-204 |
| ModuleContext | Variables.elm | 143-157 |
| Project rule setup | Variables.elm | 104-117 |
| Module visitor chain | Variables.elm | 120-134 |
| Context creators | Variables.elm | 235-277 |
| getDeclaredNamesFromPattern | Variables.elm | 1064-1099 |
| registerVariable | Variables.elm | 1736-1747 |
| markAsUsed | Variables.elm | 1769-1784 |
| makeReport | Variables.elm | 1826-1838 |
| expressionEnterVisitor | Variables.elm | 779-849 |
| expressionExitVisitor | Variables.elm | 852-862 |
| letDeclarationEnterVisitor | Variables.elm | 865-897 |
| caseBranchEnterVisitor | Variables.elm | 1014-1024 |
| caseBranchExitVisitor | Variables.elm | 1027-1029 |
| scopeWithPatternsToIgnore | Variables.elm | 1640-1645 |
| ParameterPath type | ParameterPath.elm | 23-40 |
| Nesting type | ParameterPath.elm | 35-39 |
