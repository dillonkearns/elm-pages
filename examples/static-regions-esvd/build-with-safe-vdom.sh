#!/bin/bash
# Build script that uses elm-safe-virtual-dom
# Patches the local ELM_HOME and runs elm-pages build

set -e

FORKS_DIR=".elm-safe-vdom-forks"

if [ ! -d "$FORKS_DIR" ]; then
    echo "Error: Forks not found at $FORKS_DIR"
    echo "Run ./setup-elm-safe-virtual-dom.sh first"
    exit 1
fi

# Set up local ELM_HOME
elm_home_relative="elm-stuff/elm-home"
mkdir -p "$elm_home_relative"
ELM_HOME="$(cd "$elm_home_relative" && pwd)"
export ELM_HOME

echo "Using local ELM_HOME: $ELM_HOME"

# Patch the packages into the local ELM_HOME
echo "Patching packages with elm-safe-virtual-dom..."
for package_with_version in virtual-dom/1.0.5 browser/1.0.2 html/1.0.1; do
    package="$(dirname "$package_with_version")"
    dir="$ELM_HOME/0.19.1/packages/elm/$package_with_version"
    mkdir -p "$dir"
    rm -rf "$dir/src" "$dir/artifacts.dat" "$dir/artifacts.x.dat"
    cp "$FORKS_DIR/$package/elm.json" "$dir/elm.json"
    cp -r "$FORKS_DIR/$package/src" "$dir/src"
    echo "  Patched elm/$package_with_version"
done

# Clear elm-stuff cache so patched packages are used
echo "Clearing elm-stuff cache..."
rm -rf elm-stuff/0.19.1 elm-stuff/elm-pages .elm-pages

# Run the build
echo ""
echo "Running elm-pages build..."
npm run build

echo ""
echo "Build complete! You can now serve the dist folder:"
echo "  npx serve ./dist/"
