set -ex;
yes | lamdera reset || true
npm run build:generator
npx elm-test-rs --compiler lamdera
(cd examples/routing && yes | lamdera reset || true && npm i && npm run build && npx elm-test-rs --compiler lamdera)
(cd generator/dead-code-review && npx elm-test-rs --compiler lamdera)
(cd generator/review && npx elm-test-rs --compiler lamdera)
npm run test:snapshot
elm-verify-examples --run-tests --elm-test-args '--compiler=lamdera'
(cd generator && vitest run)

# This tests for an error message until https://github.com/dillonkearns/elm-pages/issues/531 is fixed
(cd test-scripts && npm i && (npx elm-pages run src/TestInternalError.elm || true) | grep -q -- '-- Internal error ---------------')