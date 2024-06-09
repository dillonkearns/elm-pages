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
