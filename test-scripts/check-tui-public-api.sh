#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

if grep -q '"Tui.Screen.Internal"' "$repo_root/elm.json"; then
    echo "Tui.Screen.Internal should not be exposed in elm.json"
    exit 1
fi

temp_dir="$(mktemp -d "$repo_root/tui-widgets/.tmp-public-api.XXXXXX")"

cleanup() {
    rm -rf "$temp_dir"
}

trap cleanup EXIT

cp "$repo_root/tui-widgets/elm-application.json" "$temp_dir/elm.json"
mkdir -p "$temp_dir/src"

stdout_file="$temp_dir/stdout.txt"
stderr_file="$temp_dir/stderr.txt"

cat > "$temp_dir/src/Main.elm" <<'EOF'
module Main exposing (main)

import Html exposing (Html, text)
import Tui.Effect as Effect


illegalConstructorUse : String
illegalConstructorUse =
    case Effect.none of
        Effect.None ->
            "none"

        _ ->
            "other"


illegalInternalHelper : String
illegalInternalHelper =
    Effect.toBackendTask Effect.none
        |> always "helper"


main : Html msg
main =
    text (illegalConstructorUse ++ illegalInternalHelper)
EOF

set +e
(cd "$temp_dir" && npx elm make src/Main.elm --output=/dev/null >"$stdout_file" 2>"$stderr_file")
exit_code=$?
set -e

if [ "$exit_code" -eq 0 ]; then
    echo "Tui.Effect internals are still accessible from user code"
    exit 1
fi

if ! grep -Eq 'does not expose|cannot find|not exposed' "$stderr_file"; then
    echo "Expected compiler error about hidden Tui.Effect internals"
    cat "$stderr_file"
    exit 1
fi
