set -ex;
yes | lamdera reset || true
npm run build:generator
npx elm-test-rs
(cd examples/routing && yes | lamdera reset || true && npm i && npm run build && npx elm-test-rs)
(cd generator/dead-code-review && npx elm-test-rs)
(cd generator/review && npx elm-test-rs)
npm run test:snapshot
npx elmi-to-json --version
elm-verify-examples --run-tests --elm-test-args '--compiler=lamdera'
(cd generator && vitest run)
