set -ex;
npm run build:generator
npx elm-test --compiler lamdera
(cd examples/routing && npm i && npm run build && npx elm-test --compiler lamdera)
(cd generator/dead-code-review && npx elm-test --compiler lamdera)
(cd generator/server-review && npx elm-test --compiler lamdera)
(cd generator/persistent-marking-agreement-test && npx elm-test --compiler lamdera)
(cd generator/review && npx elm-test --compiler lamdera)
npm run test:snapshot
elm-verify-examples --run-tests --elm-test-args '--compiler=lamdera'
(cd generator && vitest run)

# This tests for an error message until https://github.com/dillonkearns/elm-pages/issues/531 is fixed
(cd test-scripts && npm i && (npx elm-pages run src/TestInternalError.elm || true) | grep -q -- '-- Internal error ---------------')

(cd test-scripts && npx elm-pages run src/TestBinaryRead.elm)

# Stream tests - tests gzip, unzip, command stdin handling, etc.
(cd examples/end-to-end && npm i && npx elm-pages run script/src/StreamTests.elm)

# Multipart tests - tests multipartBody encoding via busboy round-trip
(cd examples/end-to-end && npx elm-pages run script/src/MultipartTests.elm)