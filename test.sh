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
(cd generator && npx vitest run)

# This tests for an error message until https://github.com/dillonkearns/elm-pages/issues/531 is fixed
(cd test-scripts && npm i && (npx elm-pages run src/TestInternalError.elm || true) | grep -q -- '-- Internal error ---------------')

(cd test-scripts && npx elm-pages run src/TestBinaryRead.elm)

# withSchema smoke tests - verify --introspect output and normal execution
(cd test-scripts && npx elm-pages run src/TestWithSchema.elm --introspect | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["name"] == "TestWithSchema"
assert "description" in data
assert "help" in data
assert "outputSchema" in data
print("--introspect output OK")
')
(cd test-scripts && npx elm-pages run src/TestWithSchema.elm --name World | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["greeting"].startswith("Hello, World")
print("Normal execution output OK")
')
(cd test-scripts && npx elm-pages run src/TestWithSchemaDebugLog.elm --introspect | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["name"] == "TestWithSchemaDebugLog"
assert data["description"] == "Test script with a top-level Debug.log"
assert data["outputSchema"]["properties"]["status"]["type"] == "string"
print("Top-level Debug.log introspection OK")
')

# Batch introspection smoke test - verify elm-pages introspect discovers all withSchema scripts
(cd test-scripts && npx elm-pages introspect | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert isinstance(data, list), "Expected a JSON array"
assert len(data) == 3, "Expected 3 scripts, got " + str(len(data))
names = {s["name"] for s in data}
assert names == {"TestWithSchema", "TestListFiles", "TestWithSchemaDebugLog"}, "Unexpected scripts: " + str(names)
for s in data:
    assert "description" in s
    assert "help" in s
    assert "outputSchema" in s
    assert "path" in s
print("Batch introspection OK")
')

# Stream tests - tests gzip, unzip, command stdin handling, etc.
(cd examples/end-to-end && npm i && npx elm-pages run script/src/StreamTests.elm)

# File/Script utility tests - tests file operations, optional, finally, etc.
(cd examples/end-to-end && npx elm-pages run script/src/FileTests.elm)

# Multipart tests - tests multipartBody encoding via busboy round-trip
(cd examples/end-to-end && npx elm-pages run script/src/MultipartTests.elm)

# Scaffold tests - verify AddRoute with form fields generates compilable code
# Uses end-to-end example which references local src/ via source-directories
(cd examples/end-to-end && \
  npx elm-codegen install && \
  npx elm-pages run script/src/AddRoute.elm TestScaffold name:text email:text && \
  npx elm-pages gen && \
  lamdera make app/Route/TestScaffold.elm && \
  rm app/Route/TestScaffold.elm)
