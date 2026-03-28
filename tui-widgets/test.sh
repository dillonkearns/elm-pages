#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
    if [ -n "${temp_dir:-}" ] && [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi
}

trap cleanup EXIT

cd "$repo_root"

temp_dir="$(mktemp -d .tmp-tui-widgets-tests.XXXXXX)"

cp tui-widgets/elm-application.json "$temp_dir/elm.json"
ln -s "$repo_root/tui-widgets/src" "$temp_dir/src"
ln -s "$repo_root/tui-widgets/tests" "$temp_dir/tests"

cd "$temp_dir"

if [ "$#" -eq 0 ]; then
    set -- tests/*.elm
fi

npx elm-test "$@"
