#!/usr/bin/env bash
# publish-validate.sh — Validate elm-pages is ready to publish
#
# Creates an ephemeral project using:
#   - `npm pack` to emulate the published npm package
#   - a throwaway ELM_HOME to emulate the published Elm package: this repo's
#     Elm package source is put into an empty package cache, so the test
#     project compiles it as an installed package (not as source directories)
# Then runs smoke tests (build + script execution) against it.
#
# This catches issues like incompatible dependency versions in the init
# template before they reach users.
#
# The Elm compiler only accepts package versions that the package registry
# knows about, and the version being released is not published yet. So the
# local source stands in for the newest published version: it is copied into
# the throwaway cache under that version number, and the test project asks
# for that number. Everything else (the source, its dependency constraints,
# the template's dependencies) is the real thing. Your own ~/.elm is not
# touched.
#
# Prerequisites:
#   - Node.js / npm, python3, curl
#   - Internet access (to fetch Elm dependencies)
#
# Usage:
#   ./publish-validate.sh
#
# Environment variables:
#   SKIP_CLEANUP=1    Keep work directory for debugging

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

ELM_PKG_VERSION=$(python3 -c "import json; print(json.load(open('elm.json'))['version'])")
NPM_PKG_VERSION=$(node -p "require('./package.json').version")

echo "=== elm-pages publish validation ==="
echo "  Elm package: dillonkearns/elm-pages@$ELM_PKG_VERSION"
echo "  npm package: elm-pages@$NPM_PKG_VERSION"

# ── Prerequisites ────────────────────────────────────────────────────────
for cmd in node npm python3 curl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo ""
    echo "ERROR: '$cmd' is required but not found on PATH."
    exit 1
  fi
done

# ── Step 1: Version reference checks ────────────────────────────────────
echo ""
echo "--- Checking template version references ---"

FAIL=0
check_ref() {
  local file="$1" py_expr="$2" expected="$3" label="$4"
  local actual
  actual=$(python3 -c "import json; $py_expr" < "$file")
  if [ "$actual" != "$expected" ]; then
    echo "  FAIL: $label = '$actual' (expected '$expected')"
    FAIL=1
  else
    echo "  OK:   $label = $actual"
  fi
}

check_ref "generator/template/elm.json" \
  "print(json.load(open(0))['dependencies']['direct']['dillonkearns/elm-pages'])" \
  "$ELM_PKG_VERSION" "template/elm.json elm-pages version"

check_ref "generator/template/script/elm.json" \
  "print(json.load(open(0))['dependencies']['direct']['dillonkearns/elm-pages'])" \
  "$ELM_PKG_VERSION" "template/script/elm.json elm-pages version"

check_ref "generator/template/package.json" \
  "print(json.load(open(0))['devDependencies']['elm-pages'])" \
  "^$NPM_PKG_VERSION" "template/package.json npm version"

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "Version references are out of sync. Run ./publish-prep.sh first."
  exit 1
fi

# ── Step 1b: elm-review auto-fix ───────────────────────────────────────
echo ""
echo "--- Running elm-review --fix-all-without-prompt ---"
npx elm-review --fix-all-without-prompt
echo "  Done."

# ── Setup ────────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
echo ""
echo "Work directory: $WORK_DIR"

# When a smoke test fails, the compiler often only says that the dependencies
# are "not compatible". This looks through the template's dependency lists and
# says which package wants which version, and which indirect dependencies
# nothing needs. It can only look at packages the compiler got as far as
# downloading, so it is a hint, not a full check.
explain_template_dependencies() {
  echo ""
  echo "--- Looking for problems in the template's dependency lists ---"
  python3 - "$ELM_PACKAGES_DIR" "$REPO_ROOT/generator/template/elm.json" "$REPO_ROOT/generator/template/script/elm.json" <<'PYEOF'
import json, os, sys
cache, *app_elm_jsons = sys.argv[1:]


def parse(version):
    return tuple(int(n) for n in version.split('.'))


def satisfies(version, constraint):
    # "1.0.0 <= v < 2.0.0"
    low, low_op, _, high_op, high = constraint.split()
    above = parse(low) <= parse(version) if low_op == '<=' else parse(low) < parse(version)
    below = parse(version) < parse(high) if high_op == '<' else parse(version) <= parse(high)
    return above and below


def package_dependencies(name, version):
    if name == 'dillonkearns/elm-pages':
        # Only the stand-in version is in the cache, and it is this repo's source
        versions = os.listdir(os.path.join(cache, name))
        version = versions[0]
    path = os.path.join(cache, name, version, 'elm.json')
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)['dependencies']


failed = False
for path in app_elm_jsons:
    label = path.split('generator/')[-1]
    with open(path) as f:
        deps = json.load(f)['dependencies']
    pins = {**deps['direct'], **deps['indirect']}
    needed = set(deps['direct'])
    problems = []
    saw_every_package = True
    for name, version in pins.items():
        wanted = package_dependencies(name, version)
        if wanted is None:
            # Not downloaded (the compiler stopped before it got there)
            saw_every_package = False
            continue
        for dep, constraint in wanted.items():
            needed.add(dep)
            if dep not in pins:
                problems.append(f'{name} needs {dep} ({constraint}), which is not listed')
            elif not satisfies(pins[dep], constraint):
                problems.append(f'{name} needs {dep} ({constraint}), but {pins[dep]} is listed')
    for name in sorted(set(pins) - needed) if saw_every_package else []:
        problems.append(f'{name} is listed as an indirect dependency, but nothing needs it')
    if problems:
        failed = True
        print(f'  {label}')
        for problem in problems:
            print(f'    - {problem}')
if not failed:
    print('  Nothing found. See the compiler output above.')
PYEOF
}

cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -d "${ELM_PACKAGES_DIR:-}" ]; then
    explain_template_dependencies || true
  fi
  echo ""
  echo "--- Cleaning up ---"
  if [ "${SKIP_CLEANUP:-}" = "1" ]; then
    echo "  SKIP_CLEANUP=1 — keeping work directory."
    echo ""
    echo "  Test project:  $WORK_DIR/smoke-test"
    echo "  cd $WORK_DIR/smoke-test"
    echo "  export ELM_HOME=$WORK_DIR/elm-home PATH=$WORK_DIR/smoke-test/node_modules/.bin:\$PATH"
    echo ""
    echo "  To diff your changes against the template:"
    echo "    diff -ru $REPO_ROOT/generator/template $WORK_DIR/smoke-test --exclude=node_modules --exclude=elm-stuff --exclude=.elm-pages --exclude=dist --exclude=codegen"
    echo ""
    echo "  To clean up when done:"
    echo "    rm -rf $WORK_DIR"
  else
    rm -rf "$WORK_DIR"
    echo "  Removed work directory."
  fi
  if [ "$rc" -ne 0 ]; then
    echo ""
    echo "=== VALIDATION FAILED ==="
  fi
  return "$rc"
}
trap cleanup EXIT

# ── Step 2: Find the published version to stand in for ───────────────────
echo ""
echo "--- Finding the newest published Elm package version ---"
STAND_IN_VERSION=$(curl -fsSL "https://package.elm-lang.org/packages/dillonkearns/elm-pages/releases.json" \
  | python3 -c "import json,sys; print(max(json.load(sys.stdin), key=lambda v: tuple(int(n) for n in v.split('.'))))")
echo "  Local source (to be $ELM_PKG_VERSION) stands in for published $STAND_IN_VERSION"

# ── Step 3: Pack npm package ─────────────────────────────────────────────
echo ""
echo "--- Packing npm package ---"
TARBALL="$WORK_DIR/elm-pages-${NPM_PKG_VERSION}.tgz"
npm pack --pack-destination "$WORK_DIR" 2>&1 | tail -1
echo "  Created $(basename "$TARBALL") ($(du -h "$TARBALL" | cut -f1 | xargs))"

# ── Step 4: Scaffold test project from packed template ───────────────────
echo ""
echo "--- Scaffolding test project (elm-pages init) ---"

# Install the packed CLI in a runner so we can call elm-pages init
RUNNER="$WORK_DIR/runner"
mkdir -p "$RUNNER"
echo '{"name":"runner","private":true,"type":"module"}' > "$RUNNER/package.json"
(cd "$RUNNER" && npm install "$TARBALL" --save-dev 2>&1 | tail -1)

# Create the test project
(cd "$WORK_DIR" && "$RUNNER/node_modules/.bin/elm-pages" init smoke-test)

# ── Step 5: Install test project npm dependencies ────────────────────────
echo ""
echo "--- Installing test project dependencies ---"
TEST_DIR="$WORK_DIR/smoke-test"
cd "$TEST_DIR"

# Point elm-pages dep at our packed tarball instead of the npm registry
python3 -c "
import json
with open('package.json') as f:
    d = json.load(f)
d['devDependencies']['elm-pages'] = 'file:$TARBALL'
with open('package.json', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"

npm install 2>&1 | tail -5

# Make binaries (lamdera, elm, elm-pages, etc.) available on PATH
export PATH="$TEST_DIR/node_modules/.bin:$PATH"

# Verify lamdera is reachable (elm-pages uses it as the compiler)
if ! command -v lamdera &>/dev/null; then
  echo "ERROR: lamdera not found on PATH after npm install"
  exit 1
fi
echo "  lamdera $(lamdera --version) on PATH"

# ── Step 5b: Put the local Elm package into a throwaway package cache ────
echo ""
echo "--- Installing local Elm package into a throwaway ELM_HOME ---"
export ELM_HOME="$WORK_DIR/elm-home"
# The package cache folder is named after the Elm version the compiler is
# built on, which is what `lamdera --version` prints (for example 0.19.3).
ELM_PACKAGES_DIR="$ELM_HOME/$(lamdera --version)/packages"
ELM_PKG_DIR="$ELM_PACKAGES_DIR/dillonkearns/elm-pages/$STAND_IN_VERSION"
mkdir -p "$ELM_PKG_DIR"
cp -R "$REPO_ROOT/src" "$REPO_ROOT/README.md" "$REPO_ROOT/LICENSE" "$ELM_PKG_DIR/"
python3 - "$REPO_ROOT/elm.json" "$ELM_PKG_DIR/elm.json" "$STAND_IN_VERSION" elm.json script/elm.json <<'PYEOF'
import json, sys
package_src, package_dest, stand_in, *app_elm_jsons = sys.argv[1:]

# The package's own elm.json, labelled with the stand-in version
with open(package_src) as f:
    package = json.load(f)
package['version'] = stand_in
with open(package_dest, 'w') as f:
    json.dump(package, f, indent=4)

# The test project asks for the stand-in version
for path in app_elm_jsons:
    with open(path) as f:
        d = json.load(f)
    d['dependencies']['direct']['dillonkearns/elm-pages'] = stand_in
    with open(path, 'w') as f:
        json.dump(d, f, indent=4)
        f.write('\n')
PYEOF
echo "  $ELM_PKG_DIR"

# ── Step 6: Smoke test — build ───────────────────────────────────────────
echo ""
echo "--- Smoke test: npm run build ---"
npm run build
echo "  Build succeeded."

# ── Step 7: Smoke test — run script ─────────────────────────────────────
echo ""
echo "--- Smoke test: elm-pages run script/src/Stars.elm ---"
npx elm-pages run script/src/Stars.elm
echo "  Script succeeded."

# ── Step 8: Smoke test — DB feature ─────────────────────────────────────
# Exercises Pages.Db + migration infrastructure against the real installed
# package (not source-directories) so internal-import leaks get caught.
echo ""
echo "--- Smoke test: DB script (Pages.Db against installed package) ---"

# Schema lives in script source; migrations live at runtime-dir root
# (where `elm-pages run` is invoked), matching the convention in
# examples/end-to-end/.
mkdir -p db/Db/Migrate

cat > script/src/Db.elm <<'ELMEOF'
module Db exposing (Db, Todo)


type alias Db =
    { todos : List Todo }


type alias Todo =
    { title : String
    , done : Bool
    }
ELMEOF

cat > db/Db/Migrate/V1.elm <<'ELMEOF'
module Db.Migrate.V1 exposing (migrate, seed)

import Db


seed : () -> Db.Db
seed () =
    { todos = [] }


migrate : () -> Db.Db
migrate =
    seed
ELMEOF

cat > script/src/TestDb.elm <<'ELMEOF'
module TestDb exposing (run)

import BackendTask
import Pages.Db
import Pages.Script as Script exposing (Script)


run : Script
run =
    Script.withoutCliOptions
        (Pages.Db.update Pages.Db.default
            (\db -> { db | todos = [ { title = "milk", done = False } ] })
            |> BackendTask.andThen (\_ -> Script.log "DB smoke test passed.")
        )
        |> Script.withDatabasePath ".elm-pages-data/smoke.db.bin"
ELMEOF

npx elm-pages run script/src/TestDb.elm
echo "  DB smoke test succeeded."

# ── Step 9: Smoke test — test (TestApp + VirtualFS) ─────────────────────
# Exercises the generated TestApp.elm + Test.PagesProgram against the
# real installed package. Catches internal-import leaks like
# Test.BackendTask.Internal.VirtualFS that source-directory overrides
# in examples mask.
echo ""
echo "--- Smoke test: elm-pages test (TestApp compiles against installed package) ---"

mkdir -p tests

# Install elm-explorations/test. Needs to be in regular direct deps (not
# just test-dependencies) because dev-server's /_tests compile uses
# `elm make` rather than `elm-test` — test-dependencies would be invisible.
python3 - <<PYEOF
import json
path = 'elm.json'
with open(path) as f:
    d = json.load(f)
d['dependencies']['direct']['elm-explorations/test'] = '2.2.1'
d['dependencies'].setdefault('indirect', {}).pop('elm-explorations/test', None)
with open(path, 'w') as f:
    json.dump(d, f, indent=4)
    f.write('\n')
PYEOF

cat > tests/IndexTest.elm <<'ELMEOF'
module IndexTest exposing (indexTest)

import Test.BackendTask as BackendTaskTest
import Test.Html.Selector as Selector
import Test.PagesProgram as PagesProgram
import TestApp


indexTest : PagesProgram.Test
indexTest =
    PagesProgram.test "renders"
        (TestApp.start "/" BackendTaskTest.init)
        [ PagesProgram.ensureViewHas [ Selector.text "elm-pages is up and running!" ] ]
ELMEOF

npx elm-pages test tests/IndexTest.elm
echo "  test smoke test succeeded."

# ── Step 10: Smoke test — dev-server TestViewer compiles ────────────────
# `elm-pages dev` generates TestViewer.elm (importing
# Test.PagesProgram.Viewer) at elm-stuff/elm-pages/test-viewer/ for the
# /_tests browser route. Compile-path is separate from `elm-pages test`,
# so we exercise it directly here to catch internal-import leaks that
# only affect the dev server.
echo ""
echo "--- Smoke test: dev /_tests TestViewer compiles against installed package ---"

mkdir -p elm-stuff/elm-pages/test-viewer

cat > elm-stuff/elm-pages/test-viewer/TestViewer.elm <<'ELMEOF'
module TestViewer exposing (main)

import IndexTest
import Test.PagesProgram
import Test.PagesProgram.Viewer as Viewer


main : Program Viewer.Flags Viewer.Model Viewer.Msg
main =
    Viewer.app
        (Test.PagesProgram.toNamedSnapshots IndexTest.indexTest)
ELMEOF

# Set up the test-viewer elm.json the same way dev-server.js does:
# start from the project elm.json, adjust source-dirs to be relative to
# the test-viewer compile dir, add tests/ for IndexTest, and inject
# lamdera/codecs + elm/bytes (generated TestApp imports Lamdera.Wire3).
python3 - <<PYEOF
import json, os

with open('elm.json') as f:
    d = json.load(f)

dirs = [os.path.join('../../..', sd) for sd in d['source-directories']]
dirs = [sd for sd in dirs if 'test-viewer' not in sd]
dirs.append('../../../tests')
dirs.append('.')
d['source-directories'] = dirs

# Inject the same deps dev-server.js injects
d['dependencies'].setdefault('direct', {})['lamdera/codecs'] = '1.0.0'
d['dependencies'].setdefault('indirect', {}).pop('lamdera/codecs', None)
d['dependencies']['direct']['elm/bytes'] = '1.0.8'
d['dependencies'].setdefault('indirect', {}).pop('elm/bytes', None)

with open('elm-stuff/elm-pages/test-viewer/elm.json', 'w') as f:
    json.dump(d, f, indent=4)
PYEOF

(cd elm-stuff/elm-pages/test-viewer && lamdera make TestViewer.elm --output=/dev/null 2>&1 | tail -5)
echo "  dev /_tests smoke test succeeded."

# ── Step 11: Outdated dependency report ──────────────────────────────────
echo ""
echo "--- Outdated dependencies (informational) ---"

echo ""
echo "  Elm packages (template/elm.json):"
if command -v elm-outdated &>/dev/null; then
  cd "$TEST_DIR"
  elm-outdated 2>/dev/null | sed 's/^/    /' || echo "    (elm-outdated failed)"
else
  echo "    (elm-outdated not installed — https://github.com/dillonkearns/elm-outdated)"
fi

echo ""
echo "  Elm packages (template/script/elm.json):"
if command -v elm-outdated &>/dev/null; then
  cd "$TEST_DIR/script"
  elm-outdated 2>/dev/null | sed 's/^/    /' || echo "    (elm-outdated failed)"
fi

echo ""
echo "  npm packages:"
cd "$TEST_DIR"
NPM_OUTDATED=$(npm outdated 2>/dev/null || true)
if [ -n "$NPM_OUTDATED" ]; then
  echo "$NPM_OUTDATED" | sed 's/^/    /'
else
  echo "    (all up to date)"
fi

# ── Done ─────────────────────────────────────────────────────────────────
echo ""
echo "=== All publish validation checks passed! ==="
