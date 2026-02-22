#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-8888}"
BASE_URL="http://127.0.0.1:${PORT}"
NETLIFY_LOG="$PROJECT_DIR/.netlify-dev-harness.log"
NETLIFY_PID=""

cleanup() {
  if [[ -n "$NETLIFY_PID" ]] && kill -0 "$NETLIFY_PID" >/dev/null 2>&1; then
    kill "$NETLIFY_PID" >/dev/null 2>&1 || true
    wait "$NETLIFY_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

cd "$PROJECT_DIR"

echo "Building end-to-end app for Netlify runtime checks..."
npm run build:netlify

echo "Starting Netlify local server on $BASE_URL..."
rm -f "$NETLIFY_LOG"
BROWSER=none npx --yes netlify-cli@15.0.2 dev --offline --port "$PORT" --dir dist --functions functions >"$NETLIFY_LOG" 2>&1 &
NETLIFY_PID=$!

for attempt in $(seq 1 60); do
  if curl --silent --show-error --fail "$BASE_URL/frozen-views" >/dev/null 2>&1; then
    break
  fi

  if ! kill -0 "$NETLIFY_PID" >/dev/null 2>&1; then
    echo "netlify dev exited unexpectedly"
    cat "$NETLIFY_LOG"
    exit 1
  fi

  if [[ "$attempt" -eq 60 ]]; then
    echo "Timed out waiting for netlify dev on $BASE_URL"
    tail -n 120 "$NETLIFY_LOG" || true
    exit 1
  fi

  sleep 1
done

echo "Running Cypress Netlify spec..."
npx cypress run --config-file cypress.netlify.config.ts --spec cypress/e2e/frozen-views.netlify.cy.js

echo "Netlify frozen-views harness passed."
