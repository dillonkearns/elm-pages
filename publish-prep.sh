#!/usr/bin/env bash
# publish-prep.sh — Prepare elm-pages for publishing
#
# 1. Updates compatibility keys (Elm + JS)
# 2. Syncs template version references to match current package versions
# 3. Resolves template dependency trees using elm-wrap (if available)
#
# After running this, review changes with `git diff generator/template/`
# then run `./publish-validate.sh` to verify everything builds correctly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
export PATH="$REPO_ROOT/node_modules/.bin:$PATH"

echo "=== elm-pages publish prep ==="

# --- Step 1: Update compatibility keys ---
echo ""
echo "--- Updating compatibility keys ---"
node update-compatibility-keys.js
echo "  Done."

# --- Read current versions ---
ELM_VERSION=$(python3 -c "import json; print(json.load(open('elm.json'))['version'])")
NPM_VERSION=$(node -p "require('./package.json').version")
echo ""
echo "  Elm package version: $ELM_VERSION"
echo "  npm package version: $NPM_VERSION"

# --- Step 2: Update template version references ---
echo ""
echo "--- Updating template version references ---"

update_elm_json_version() {
  local file="$1" version="$2"
  local old
  old=$(python3 -c "import json; print(json.load(open('$file'))['dependencies']['direct'].get('dillonkearns/elm-pages','MISSING'))")
  python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
d['dependencies']['direct']['dillonkearns/elm-pages'] = '$version'
with open('$file', 'w') as f:
    json.dump(d, f, indent=4)
    f.write('\n')
"
  echo "  $file: elm-pages $old -> $version"
}

update_elm_json_version "generator/template/elm.json" "$ELM_VERSION"
update_elm_json_version "generator/template/script/elm.json" "$ELM_VERSION"

# Update template package.json npm version
OLD_NPM=$(python3 -c "import json; print(json.load(open('generator/template/package.json'))['devDependencies'].get('elm-pages','MISSING'))")
python3 -c "
import json
with open('generator/template/package.json') as f:
    d = json.load(f)
d['devDependencies']['elm-pages'] = '$NPM_VERSION'
with open('generator/template/package.json', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
echo "  generator/template/package.json: elm-pages $OLD_NPM -> $NPM_VERSION"

# --- Step 3: Resolve template dependencies with elm-wrap ---
echo ""
echo "--- Resolving template dependencies ---"

if ! command -v wrap &>/dev/null; then
  echo "  SKIP: elm-wrap not found. Template indirect deps may need manual updates."
  echo "  Install: brew tap dsimunic/elm-wrap && brew install elm-wrap"
  echo ""
  echo "=== Publish prep complete (dep resolution skipped) ==="
  echo "Run ./publish-validate.sh to check for dependency issues."
  exit 0
fi

# Register local Elm package for local-dev
wrap install --local-dev dillonkearns/elm-pages -y -q

WORK_DIR=$(mktemp -d)
cleanup() {
  wrap repository local-dev clear dillonkearns/elm-pages "$ELM_VERSION" 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

resolve_template_deps() {
  local template_dir="$1" label="$2" temp_dir="$3"
  echo "  Resolving $label..."

  cp -r "$template_dir" "$temp_dir"
  # Ensure source-directories exist so the solver doesn't complain
  local source_dirs
  source_dirs=$(python3 -c "import json; [print(d) for d in json.load(open('$temp_dir/elm.json')).get('source-directories',[])]")
  while IFS= read -r dir; do
    mkdir -p "$temp_dir/$dir"
  done <<< "$source_dirs"

  cd "$temp_dir"
  rm -rf elm-stuff

  # Remove elm-pages from direct deps and clear all indirect deps.
  # This forces `wrap install` to do a full dependency resolution
  # instead of saying "already installed" and skipping.
  python3 << PYEOF
import json
with open('elm.json') as f:
    d = json.load(f)
d['dependencies']['direct'].pop('dillonkearns/elm-pages', None)
d['dependencies']['indirect'] = {}
with open('elm.json', 'w') as f:
    json.dump(d, f, indent=4)
    f.write('\n')
PYEOF

  # Install elm-pages via wrap — the solver resolves all transitive deps
  if WRAP_ELM_COMPILER_PATH=lamdera wrap install dillonkearns/elm-pages -y -q 2>/dev/null; then
    if ! diff -q "$temp_dir/elm.json" "$REPO_ROOT/$template_dir/elm.json" &>/dev/null; then
      cp "$temp_dir/elm.json" "$REPO_ROOT/$template_dir/elm.json"
      echo "    Updated $label."
    else
      echo "    $label already consistent."
    fi
  else
    echo "    WARNING: auto-resolve failed for $label. Check indirect deps manually."
  fi
  cd "$REPO_ROOT"
}

resolve_template_deps "generator/template" "template/elm.json" "$WORK_DIR/main"

# For script/elm.json, set up the parent directory structure it expects
# (source-directories includes "../codegen")
SCRIPT_PARENT="$WORK_DIR/script-parent"
mkdir -p "$SCRIPT_PARENT"
cp -r generator/template/codegen "$SCRIPT_PARENT/codegen" 2>/dev/null || mkdir -p "$SCRIPT_PARENT/codegen"
resolve_template_deps "generator/template/script" "template/script/elm.json" "$SCRIPT_PARENT/script"

echo ""
echo "=== Publish prep complete ==="
echo ""
echo "Review changes: git diff generator/template/"
echo "Validate:       ./publish-validate.sh"
