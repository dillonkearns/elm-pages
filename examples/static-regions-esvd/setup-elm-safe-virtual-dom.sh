#!/bin/bash
# Setup script for elm-safe-virtual-dom
# Run this once to clone the forked packages

set -e

FORKS_DIR=".elm-safe-vdom-forks"

if [ -d "$FORKS_DIR" ]; then
    echo "Forks directory already exists at $FORKS_DIR"
    echo "To re-clone, delete the directory first: rm -rf $FORKS_DIR"
    exit 0
fi

echo "Cloning lydell's forked Elm packages..."
mkdir -p "$FORKS_DIR"
cd "$FORKS_DIR"

git clone --depth 1 https://github.com/lydell/virtual-dom.git
git clone --depth 1 https://github.com/lydell/browser.git
git clone --depth 1 https://github.com/lydell/html.git

echo ""
echo "Setup complete! Forks cloned to $FORKS_DIR"
echo ""
echo "Now you can run:"
echo "  npm install"
echo "  ./build-with-safe-vdom.sh"
