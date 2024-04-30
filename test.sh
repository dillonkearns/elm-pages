set -ex;
yes | lamdera reset || true
npm run build:generator
npm install --save-dev @rollup/rollup-linux-x64-gnu
npx elm-test-rs --compiler lamdera
(cd examples/routing && yes | lamdera reset || true && npm install --save-dev @rollup/rollup-linux-x64-gnu && npm install && npm run build && npx elm-test-rs --compiler lamdera)
(cd generator/dead-code-review && npx elm-test-rs --compiler lamdera)
(cd generator/review && npx elm-test-rs --compiler lamdera)
npm run test:snapshot
elm-verify-examples --run-tests --elm-test-args '--compiler=lamdera'
(cd generator && vitest run)
