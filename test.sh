set -ex;
root=`pwd`
yes | lamdera reset || true
elm-test-rs --compiler=lamdera
cd examples/routing && npm i && npm run build && elm-test-rs --compiler=lamdera && cd $root
(cd generator/dead-code-review && elm-test-rs --compiler=lamdera)
(cd generator/review && elm-test-rs --compiler=lamdera)
npm run test:snapshot
npx elmi-to-json --version
elm-verify-examples --run-tests --elm-test-args '--compiler=lamdera'
cd generator && mocha && cd $root
