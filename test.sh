set -ex;
root=`pwd`
yes | lamdera reset || true
elm-test-rs --compiler=lamdera
cd examples/routing && npm i && npm run build && elm-test-rs --compiler=lamdera && cd $root
npm run test:snapshot
npx elmi-to-json --version
elm-verify-examples --run-tests --elm-test-args '--compiler=lamdera'
cd generator && mocha && cd $root
