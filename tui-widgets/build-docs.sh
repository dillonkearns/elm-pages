#!/usr/bin/env bash
# Build docs.json for the tui-widgets package.
#
# Runs `elm make --docs=docs.json` against the package `elm.json`. The
# main elm-pages package is resolved through the usual Elm package cache;
# for local development it's convenient to symlink
# ~/.elm/0.19.1/packages/dillonkearns/elm-pages/<version> to the root of
# this repo so changes in ../src are picked up without publishing.
#
# The Elm compiler aggressively caches build artifacts in `artifacts.dat`
# and `artifacts.x.dat` files, both inside this package and inside the
# symlinked elm-pages source tree. Stale caches will show up here as
# "module not found" errors for symbols that obviously exist. Clearing
# them (the `rm -f` calls below) is cheap and avoids that class of ghost
# failure entirely.

set -euo pipefail

cd "$(dirname "$0")"

# Wipe stale caches: both the tui-widgets elm-stuff and any artifacts.dat
# in a sibling elm-pages checkout that may be acting as the resolved
# package source.
rm -rf elm-stuff
rm -f ../artifacts.dat ../artifacts.x.dat

# Build docs against the package elm.json.
npx elm make --docs=docs.json

echo ""
echo "Wrote tui-widgets/docs.json"
