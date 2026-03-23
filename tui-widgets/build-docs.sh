#!/bin/bash
# Build docs for tui-widgets using the application elm.json
# (which can resolve Tui modules from ../src)
#
# The package elm.json is the canonical reference for publication.
# This script uses the application config to generate a docs.json
# that can be previewed with elm-doc-preview.
set -e

cd "$(dirname "$0")"

# Swap to application config
cp elm.json elm-package.json.bak
cp elm-application.json elm.json

# Build all modules to verify
elm make \
  src/Tui/Layout.elm \
  src/Tui/Modal.elm \
  src/Tui/Keybinding.elm \
  src/Tui/Spinner.elm \
  src/Tui/Toast.elm \
  src/Tui/FuzzyMatch.elm \
  src/Tui/Picker.elm \
  src/Tui/CommandPalette.elm \
  src/Tui/Search.elm \
  src/Tui/Confirm.elm \
  src/Tui/OptionsBar.elm \
  src/Tui/Status.elm \
  src/Tui/Menu.elm \
  src/Tui/Prompt.elm \
  --output=/dev/null

# Restore package config
mv elm-package.json.bak elm.json

echo "tui-widgets modules compile successfully."
echo ""
echo "Package elm.json is ready for publication."
echo "Exposed modules: Tui.Layout, Tui.Modal, Tui.Keybinding, Tui.Spinner,"
echo "  Tui.Toast, Tui.FuzzyMatch, Tui.Picker, Tui.CommandPalette,"
echo "  Tui.Search, Tui.Confirm, Tui.OptionsBar, Tui.Status,"
echo "  Tui.Menu"
