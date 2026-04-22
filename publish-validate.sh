#!/usr/bin/env bash
# publish-validate.sh — Validate elm-pages is ready to publish
#
# Creates an ephemeral project using:
#   - `npm pack` to emulate the published npm package
#   - `elm-wrap` to emulate the published Elm package
# Then runs smoke tests (build + script execution) against it.
#
# This catches issues like incompatible dependency versions in the init
# template before they reach users.
#
# Prerequisites:
#   - elm-wrap: brew tap dsimunic/elm-wrap && brew install elm-wrap
#   - Node.js / npm
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
for cmd in wrap node npm python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo ""
    echo "ERROR: '$cmd' is required but not found on PATH."
    [[ "$cmd" == "wrap" ]] && echo "  Install: brew tap dsimunic/elm-wrap && brew install elm-wrap"
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
  "$NPM_PKG_VERSION" "template/package.json npm version"

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

cleanup() {
  local rc=$?
  echo ""
  echo "--- Cleaning up ---"
  wrap repository local-dev clear dillonkearns/elm-pages "$ELM_PKG_VERSION" 2>/dev/null || true
  # Remove the ELM_HOME symlink that elm-wrap's --local-dev creates.
  # `wrap repository local-dev clear` only removes wrap's tracking metadata,
  # not the actual symlink in ELM_HOME, which can poison future builds.
  local elm_home="${ELM_HOME:-$HOME/.elm}"
  local pkg_path="$elm_home/0.19.1/packages/dillonkearns/elm-pages/$ELM_PKG_VERSION"
  if [ -L "$pkg_path" ]; then
    rm "$pkg_path"
    echo "  Removed elm-wrap symlink: $pkg_path"
  fi
  if [ "${SKIP_CLEANUP:-}" = "1" ]; then
    echo "  SKIP_CLEANUP=1 — keeping work directory."
    echo ""
    echo "  Test project:  $WORK_DIR/smoke-test"
    echo "  cd $WORK_DIR/smoke-test"
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

# ── Step 2: Register local Elm package with elm-wrap ─────────────────────
echo ""
echo "--- Registering local Elm package with elm-wrap ---"
wrap install --local-dev dillonkearns/elm-pages -y -q
echo "  Registered dillonkearns/elm-pages@$ELM_PKG_VERSION from $REPO_ROOT"

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

# ── Step 9: Outdated dependency report ───────────────────────────────────
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
