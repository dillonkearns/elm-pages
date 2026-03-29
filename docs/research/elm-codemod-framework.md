# Research: An Elm Codemod Framework (elm-review + elm-pages)

## The Problem Space

elm-pages currently orchestrates a sophisticated multi-step codemod pipeline using elm-review, elm-codegen, and a lot of custom JavaScript glue. The pipeline:

1. **Copies source directories** into `elm-stuff/elm-pages/{client,server}/`
2. **Patches elm.json** files with rewritten source-directories and added dependencies
3. **Generates temporary modules** (Route.elm, Pages.elm) so elm-review can compile the project
4. **Runs elm-review** in analysis-only mode to extract structured data (ephemeral field maps)
5. **Runs elm-review again** with `--fix-all-without-prompt` to apply transformations
6. **Verifies** that fixes were actually applied (because elm-review can fail silently)
7. **Compiles** the transformed source with `elm make`
8. **Post-processes** compiled JS (frozen view adoption patches, terser)

This works, but it's fragile, hard to extend, and full of workarounds. The question: **can we build a proper codemod framework that makes this clean?**

---

## Current Pain Points

### 1. elm-review as a codemod tool is a square peg in a round hole

elm-review was designed for **linting**: find problems, report them, optionally suggest fixes. Using it for **codemods** (intentional, mandatory transformations) creates friction:

- **No structured output channel.** The only way to pass data back from an elm-review rule to the JS build layer is to embed JSON inside error message strings:
  ```elm
  Rule.error
      { message = "EPHEMERAL_FIELDS_JSON:{\"module\":\"Route.Blog\",\"ephemeralFields\":[\"renderedMarkdown\"]}"
      , details = [ "Parsed by codegen to determine routes with ephemeral fields." ]
      }
      range
  ```
  This is a hack. The build system then JSON-parses these "error messages" to extract analysis results.

- **Exit code ambiguity.** elm-review returns non-zero both for "I found lint errors" and "something went wrong." The JS layer has to parse the JSON output to distinguish `type: "error"` (tool failure) from `type: "review-errors"` (analysis results that happen to have non-zero exit).

- **Silent fix failures.** elm-review may report that fixes were applied when they weren't. elm-pages has a `verifyEphemeralTypesExist()` step that scans output files to confirm the `type alias Ephemeral` declarations actually exist.

- **elm-format dependency.** Fix application requires elm-format. If it's missing, the entire optimization is silently skipped. This is an elm-review limitation, not an elm-pages choice.

- **Two-pass overhead.** Because elm-review doesn't separate "analysis" from "fix application," elm-pages runs it twice: once for analysis (capture structured output), once for fixes.

### 2. Source directory juggling is error-prone

The build creates shadow copies of the user's source:
- `./app/` -> `./elm-stuff/elm-pages/client/app/` (force-copy, not mtime-based)
- `./app/` -> `./elm-stuff/elm-pages/server/app/` (force-copy)

Force-copy is needed because codemods modify the copies, making their mtime newer than the originals. On subsequent builds, an mtime-based copy would skip the copy and analyze already-transformed files.

Each shadow directory needs its own `elm.json` with path-prefix gymnastics (`../../../` for 3-level nesting), dependency additions, and source-directory filtering.

### 3. Three separate elm-review configs

```
generator/review/          -- validation only (NoInvalidFreeze, NoContractViolations)
generator/dead-code-review/ -- client transforms (DeadCodeEliminateData, StaticViewTransform)
generator/server-review/    -- server transforms (ServerDataTransform)
```

Each is a separate Elm project with its own `elm.json`, `ReviewConfig.elm`, and duplicated shared modules (via symlinks or copies in `generator/shared/`). Adding a new codemod step means creating an entire new elm-review project.

### 4. Agreement validation is manual

Client and server transforms must agree on which fields are ephemeral. This is validated by `compareEphemeralFields()` in JS after both codemods run. A disagreement means a runtime bytes decode error. The agreement is checked *after the fact* rather than being *structurally guaranteed*.

---

## Prior Art from Other Ecosystems

### jscodeshift (JavaScript)

Facebook's codemod runner. Key ideas:
- **Transforms are just functions**: `(fileInfo, api, options) => string`. Receive source, return transformed source.
- **jQuery-like collection API** over the AST: `root.find(j.FunctionDeclaration).forEach(path => { ... })`.
- **Runner handles the boring stuff**: file discovery, parallel workers, dry-run mode, git integration.
- **Composable transforms**: Multiple transforms can be chained.

**Lesson for Elm**: Separate the "find files, copy them, manage shadow dirs" orchestration from the "transform this AST" logic. Let users (and elm-pages internally) write transforms as pure functions.

### ts-morph (TypeScript)

- **In-memory filesystem**: All changes stay in memory until explicitly flushed. No need for shadow directories.
- **Type-aware transforms**: Uses the full TypeScript compiler, so transforms can reason about types, not just syntax.
- **Ergonomic navigation**: `sourceFile.getFunction("foo").getParameters()` instead of raw visitor patterns.

**Lesson for Elm**: An in-memory representation would eliminate the shadow-directory pattern entirely. elm-review already has the AST in memory; the problem is getting transformed source *out* without going through the fix mechanism.

### Cargo-fix + Clippy (Rust)

- **Applicability levels**: Fixes are tagged as `MachineApplicable`, `MaybeIncorrect`, or `HasPlaceholders`. Only `MachineApplicable` fixes are auto-applied.
- **Compiler integration**: cargo-fix intercepts compiler suggestions and applies them. The fix tool doesn't need its own parser.

**Lesson for Elm**: Having explicit confidence levels on transforms would help. Some of elm-pages' codemods are "always correct" (e.g., renaming `Data` to `Ephemeral`), others are "correct if our analysis is right" (e.g., removing fields). The framework could treat these differently.

### Babel Plugins (JavaScript)

- **Visitor pattern**: Plugins declare which AST node types they care about. The framework handles traversal.
- **Path API**: Nodes are wrapped in "paths" that know their parent, siblings, scope. Transforms can navigate the tree contextually.
- **Plugin composition**: Multiple plugins run in a single pass. Each plugin sees the output of the previous one.

**Lesson for Elm**: elm-review already uses visitors, but doesn't compose multiple rules in a single pass for codemod purposes. A codemod framework could allow rule chaining within a single compilation pass.

### Elixir Styler (Adobe)

- **Hooks into `mix format`**: Runs as a formatter plugin, so it's part of the normal developer workflow.
- **Source-aware rewrites**: Uses the Sourceror library to manipulate AST while preserving comments and formatting.

**Lesson for Elm**: Integrating codemods into the build tool (elm-pages) rather than treating them as external lint passes is the right call. The question is how to make the integration less ad-hoc.

---

## Design Ideas

### Idea 1: `elm-codemod` as a first-class concept

Instead of shoehorning codemods into elm-review's lint-and-fix model, define a **codemod rule type** that's distinct from a lint rule:

```elm
-- A codemod rule returns transformed source, not error messages
type alias CodemodRule =
    { name : String
    , transform : ProjectContext -> Module -> TransformResult
    }

type TransformResult
    = NoChange
    | Transformed String             -- new source text
    | TransformedWithData String Json.Value  -- new source + structured output
```

Key differences from elm-review rules:
- **No error/fix indirection.** Transform functions return new source directly.
- **Structured output channel.** `TransformedWithData` lets rules pass machine-readable data back to the orchestrator without JSON-in-error-message hacks.
- **Single pass.** Analysis and transformation happen together.

This could be implemented as a layer on top of elm-review's AST infrastructure (reusing its parser, module graph, `ModuleNameLookupTable`, etc.) without being constrained by its reporting model.

### Idea 2: Build Environments as a first-class abstraction

The shadow-directory + elm.json patching pattern is really defining **build environments**: "compile this set of source files with these dependencies and these generated modules." Abstract it:

```javascript
// Conceptual API
const clientEnv = buildEnvironment({
  name: "client",
  sourceFrom: ["./app"],
  generatedModules: ["Main.elm", "Route.elm", "Pages.elm"],
  extraDependencies: { "lamdera/codecs": "1.0.0" },
  codemods: [
    deadCodeElimination({ target: "client" }),
    staticViewTransform(),
  ],
});

const serverEnv = buildEnvironment({
  name: "server",
  sourceFrom: ["./app"],
  generatedModules: ["Main.elm", "Route.elm"],
  extraDependencies: { "lamdera/codecs": "1.0.0" },
  codemods: [
    serverDataTransform(),
  ],
});

// The framework handles: shadow dirs, elm.json rewriting, force-copy,
// temporary module generation, codemod execution, verification
const clientResult = await clientEnv.compile({ optimize: true });
const serverResult = await serverEnv.compile();

// Agreement validation built into the framework
assertAgreement(clientResult.metadata, serverResult.metadata, {
  key: "ephemeralFields",
  formatError: formatDisagreementError,
});
```

This would:
- Encapsulate the shadow-directory dance
- Make elm.json patching declarative
- Chain codemods explicitly
- Handle force-copy / mtime invalidation internally
- Provide a natural place for agreement validation

### Idea 3: elm-codegen as the transformation backend

elm-codegen already knows how to generate well-formatted Elm code. Instead of having elm-review produce text diffs that require elm-format to apply, codemods could:

1. **Analyze** with elm-review's AST (reading)
2. **Generate** replacement code with elm-codegen (writing)

```elm
-- Codemod rule using elm-codegen for output
serverDataTransform : CodemodRule
serverDataTransform =
    { name = "ServerDataTransform"
    , transform = \context module ->
        case analyzeDataType module of
            Nothing -> NoChange
            Just { allFields, ephemeralFields, persistentFields } ->
                let
                    ephemeralTypeAlias =
                        Elm.alias "Ephemeral" (List.map fieldToAnnotation allFields)

                    narrowedDataAlias =
                        Elm.alias "Data" (List.map fieldToAnnotation persistentFields)

                    conversionFn =
                        Elm.function "ephemeralToData"
                            [ ( "ephemeral", Just (Elm.Annotation.named [] "Ephemeral") ) ]
                            (\[ ephemeral ] ->
                                Elm.record
                                    (List.map (\f -> ( f.name, Elm.get f.name ephemeral )) persistentFields)
                            )
                in
                TransformedWithData
                    (Elm.render [ ephemeralTypeAlias, narrowedDataAlias, conversionFn ])
                    (encodeEphemeralFields ephemeralFields)
    }
```

Benefits:
- **No elm-format dependency.** elm-codegen produces formatted code.
- **Type-safe code generation.** Can't produce syntactically invalid Elm.
- **Composable.** elm-codegen expressions compose naturally.

Challenge: elm-codegen generates *new* code well but doesn't do *surgical edits* to existing code. You'd need a way to splice generated fragments into existing modules.

### Idea 4: Pipeline DSL

Make the full build pipeline declarative and inspectable:

```javascript
const pipeline = elmPages.pipeline({
  validate: [
    elmReview.rule("NoInvalidFreeze"),
    elmReview.rule("NoContractViolations"),
  ],

  client: {
    codemods: [
      codemod("DeadCodeEliminateData"),
      codemod("StaticViewTransform"),
    ],
    postCompile: [
      frozenViewAdoption(),
      terser(),
    ],
  },

  server: {
    codemods: [
      codemod("ServerDataTransform"),
    ],
    postCompile: [
      forceThunks(),
    ],
  },

  agreements: [
    { key: "ephemeralFields", between: ["client", "server"] },
  ],
});
```

This makes the build pipeline:
- **Readable**: You can see the full sequence at a glance
- **Extensible**: Users could add custom codemod steps
- **Testable**: Individual steps can be tested in isolation
- **Debuggable**: The framework can log each step's inputs/outputs

### Idea 5: Hybrid approach - elm-review for analysis, direct AST transforms for rewrites

Keep elm-review for what it's great at (project-wide analysis with `ModuleNameLookupTable`, cross-module type resolution, visitor-based pattern matching) but replace the fix mechanism with direct source manipulation:

```
┌─────────────────────────────────────┐
│         elm-review analysis         │
│  (visitors, lookups, type info)     │
│                                     │
│  Output: structured analysis data   │
│  (not fixes, not error messages)    │
└──────────────┬──────────────────────┘
               │ JSON / structured data
               ▼
┌─────────────────────────────────────┐
│      Transform engine (JS/Elm)      │
│                                     │
│  - Receives analysis results        │
│  - Applies transforms to source     │
│  - Uses elm-codegen for generation  │
│  - Handles splicing into modules    │
└──────────────┬──────────────────────┘
               │ transformed source files
               ▼
┌─────────────────────────────────────┐
│         elm make / compile          │
└─────────────────────────────────────┘
```

This is essentially what elm-pages already does with the two-pass system, but made explicit and clean:
- Pass 1 becomes "analysis" (the elm-review rules' *real* job)
- Pass 2 becomes "transform" (a separate concern entirely)

The analysis rules would export structured data through a proper channel, not through error messages. The transform engine would consume that data and produce source files, using elm-codegen for any generated code.

---

## What Would Make This Useful Beyond elm-pages?

An elm-codemod framework could serve:

1. **elm-pages itself** - Replace the current ad-hoc pipeline with something maintainable
2. **Library authors** - Provide codemods for major version upgrades (like jscodeshift does for React)
3. **Elm tooling** - Enable IDE-level refactorings that are more complex than what elm-review supports today
4. **Custom build pipelines** - Anyone who needs to compile multiple variants of an Elm app (different targets, feature flags, dead code paths)

### The key insight from elm-pages

elm-pages has proven that Elm's AST is rich enough to support sophisticated codemods:
- **50+ patterns tracked** for field usage analysis (direct access, let bindings, helper functions, pipes, destructuring, lambdas, case expressions)
- **Cross-module analysis** via `ModuleNameLookupTable` and helper function tracking
- **Conservative correctness** strategy that prefers de-optimization over bugs
- **Taint tracking** for model-derived values

This analysis infrastructure is genuinely powerful. The problem isn't the analysis - it's the plumbing around it.

---

## Concrete Next Steps

### Phase 1: Clean up the IPC

Replace the JSON-in-error-message hack with a proper communication channel:
- Option A: elm-review `--extract` flag (if supported or can be proposed upstream)
- Option B: Write analysis results to a temp file from the elm-review rule's `finalEvaluation`
- Option C: A custom elm-review reporter that outputs structured data alongside the normal report

### Phase 2: Build Environment abstraction

Factor out the shadow-directory / elm.json patching / force-copy logic into a reusable `BuildEnvironment` class that handles:
- Creating and managing shadow directories
- Rewriting elm.json with configurable source paths and dependencies
- Generating placeholder modules that codemods need for compilation
- Cleaning up and invalidating caches

### Phase 3: Codemod runner

Build a thin orchestration layer that:
- Takes a list of codemod rules and a build environment
- Runs analysis (via elm-review or a dedicated analysis tool)
- Applies transforms (via elm-codegen, direct source manipulation, or a hybrid)
- Validates results (agreement checks, file verification)
- Reports structured results back to the caller

### Phase 4: elm-codegen integration for generation

For codemods that *generate* code (like the `ephemeralToData` function or `type alias Ephemeral`), use elm-codegen instead of string manipulation in elm-review fixes. This eliminates the elm-format dependency and ensures valid output.

### Phase 5: User-facing API (if extracting as a standalone tool)

If this becomes a general-purpose Elm codemod framework:
- Define a codemod authoring API (building on elm-review's visitor pattern)
- Provide a CLI runner (`elm-codemod run MyTransform --target ./src`)
- Support dry-run, diff preview, rollback
- Integration with elm-review for projects that want both linting and codemods

---

## Open Questions

1. **Should analysis stay in Elm or move to JS?** elm-review's Elm-based analysis is powerful (type info, module resolution) but the IPC is painful. A JS-based AST analyzer (using `elm-syntax` compiled to JS?) would eliminate the IPC problem but lose elm-review's infrastructure.

2. **How much of elm-review to keep?** The visitor pattern + `ModuleNameLookupTable` + cross-module analysis is valuable. The fix mechanism + elm-format dependency + error-message reporting is not. Can we fork/extend elm-review to support a "codemod mode"?

3. **Where does elm-codegen fit in the analysis?** elm-codegen is great for *generation* but the current analysis is all about *reading and understanding* existing code. The bridge between "I analyzed this module's Data type" and "here's the generated replacement" needs careful design.

4. **Multi-target builds as a core concept?** elm-pages needs client + server builds. Is this general enough to be a framework feature, or should it stay in elm-pages' build logic?

5. **Incremental codemods?** Currently every build does a fresh copy + full codemod pass. Could we cache analysis results and only re-transform changed modules? This would require understanding the dependency graph.
