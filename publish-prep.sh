#!/usr/bin/env bash
# publish-prep.sh — Prepare elm-pages for publishing
#
# 1. Updates compatibility keys (Elm + JS)
# 2. Syncs template version references to match current package versions
#
# After running this, review changes with `git diff generator/template/`
# then run `./publish-validate.sh` to verify everything builds correctly.
# That script also checks the template's dependency lists against this
# version of the Elm package, and says what to change if they do not fit.

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

# Update template package.json npm version (with a caret, like elm-pages-starter)
OLD_NPM=$(python3 -c "import json; print(json.load(open('generator/template/package.json'))['devDependencies'].get('elm-pages','MISSING'))")
python3 -c "
import json
with open('generator/template/package.json') as f:
    d = json.load(f)
d['devDependencies']['elm-pages'] = '^$NPM_VERSION'
with open('generator/template/package.json', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
echo "  generator/template/package.json: elm-pages $OLD_NPM -> ^$NPM_VERSION"

echo ""
echo "=== Publish prep complete ==="
echo ""
echo "Review changes: git diff generator/template/"
echo "Validate:       ./publish-validate.sh"
echo ""
echo "publish-validate.sh builds a project from the template against this"
echo "version of the Elm package, and reports any template dependency that"
echo "needs to change (the lists in generator/template/elm.json and"
echo "generator/template/script/elm.json are edited by hand)."
