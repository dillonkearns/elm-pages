set -ex;
npm run build:generator
# Exclude tui-widgets tests (LayoutTests, MiniGitTests, KeybindingTests) — they
# import from tui-widgets/src which isn't in the root package source-directories.
# Those tests are validated via the script build (script/elm.json includes tui-widgets/src).
npx elm-test --compiler lamdera tests/ApiRouteTests.elm tests/CookieTest.elm tests/DbTestTests.elm tests/ExampleScriptTest.elm tests/FilePathTest.elm tests/FormDataTest.elm tests/GlobMatchTests.elm tests/HeadTests.elm tests/PathTests.elm tests/RouteTests.elm tests/ScriptTestTests.elm tests/SetCookieTest.elm tests/StaticHttpRequestsTests.elm tests/StaticResponsesTests.elm tests/TuiTests.elm
(cd examples/routing && npm ci && npm run build && npx elm-test --compiler lamdera)
(cd generator/dead-code-review && npx elm-test --compiler lamdera)
(cd generator/server-review && npx elm-test --compiler lamdera)
(cd generator/persistent-marking-agreement-test && npx elm-test --compiler lamdera)
(cd generator/review && npx elm-test --compiler lamdera)
npm run test:snapshot
elm-verify-examples --run-tests --elm-test-args '--compiler=lamdera'
(cd generator && npx vitest run)

# This tests for an error message until https://github.com/dillonkearns/elm-pages/issues/531 is fixed
(cd test-scripts && npm ci && (npx elm-pages run src/TestInternalError.elm || true) | grep -q -- '-- Internal error ---------------')

(cd test-scripts && npx elm-pages run src/TestBinaryRead.elm)

# withSchema smoke tests - verify --introspect-cli output and normal execution
(cd test-scripts && npx elm-pages run src/TestWithSchema.elm --introspect-cli | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["name"] == "TestWithSchema"
assert "description" in data
assert "help" in data
assert "inputSchema" in data
assert data["inputSchema"]["$schema"] == "http://json-schema.org/draft-07/schema#"
assert data["inputSchema"]["type"] == "object"
assert data["inputSchema"]["additionalProperties"] is False
assert "$cli" in data["inputSchema"]["properties"]
assert data["inputSchema"]["properties"]["$cli"]["additionalProperties"] is False
assert "name" in data["inputSchema"]["properties"]
assert data["inputSchema"]["properties"]["name"]["x-cli-kind"] == "keyword"
assert "outputSchema" in data
print("--introspect-cli output OK")
')
(cd test-scripts && npx elm-pages run src/TestWithSchema.elm --name World | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["greeting"].startswith("Hello, World")
print("Normal execution output OK")
')
(cd test-scripts && npx elm-pages run src/TestWithSchemaDebugLog.elm --introspect-cli | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["name"] == "TestWithSchemaDebugLog"
assert data["description"] == "Test script with a top-level Debug.log"
assert data["outputSchema"]["properties"]["status"]["type"] == "string"
print("Top-level Debug.log introspection OK")
')

# Typed schema smoke test - verify typed options produce correct JSON Schema types and JSON input works
(cd test-scripts && npx elm-pages run src/TestDbSchema.elm --introspect-cli | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["name"] == "TestDbSchema"
props = data["inputSchema"]["properties"]
assert props["limit"]["type"] == "integer", "Expected integer type for limit"
assert props["limit"]["x-cli-kind"] == "keyword"
assert props["table"]["type"] == "string"
assert props["verbose"]["type"] == "boolean"
assert props["verbose"]["x-cli-kind"] == "flag"
print("Typed schema introspection OK")
')
(cd test-scripts && npx elm-pages run src/TestDbSchema.elm --table users --limit 2 | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["table"] == "users"
assert data["rowCount"] == 2
assert len(data["rows"]) == 2
print("Typed CLI execution OK")
')
(cd test-scripts && json="{\"table\":\"products\",\"limit\":1,\"verbose\":true,\"\$cli\":{}}" && npx elm-pages run src/TestDbSchema.elm "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["table"] == "products"
assert data["rowCount"] == 1
print("JSON input mode OK")
')
(cd test-scripts && json="{\"title\":\"Buy groceries\",\"\$cli\":{\"subcommand\":\"add\"}}" && npx elm-pages run src/TestTaskManager.elm "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert data["action"] == "added"
assert data["tasks"][0]["title"] == "Buy groceries"
print("JSON subcommand input mode OK")
')

# Batch introspection smoke test - verify elm-pages introspect discovers all withSchema scripts
(cd test-scripts && npx elm-pages introspect | python3 -c '
import sys, json
data = json.load(sys.stdin)
assert isinstance(data, list), "Expected a JSON array"
assert len(data) == 5, "Expected 5 scripts, got " + str(len(data))
names = {s["name"] for s in data}
assert names == {"TestWithSchema", "TestListFiles", "TestWithSchemaDebugLog", "TestDbSchema", "TestTaskManager"}, "Unexpected scripts: " + str(names)
for s in data:
    assert "description" in s
    assert "help" in s
    assert "inputSchema" in s
    schema = s["inputSchema"]
    # Multi-subcommand scripts use anyOf, single-command scripts use type+properties
    if "anyOf" in schema:
        assert all("$cli" in variant["properties"] for variant in schema["anyOf"])
    else:
        assert schema["type"] == "object"
        assert "$cli" in schema["properties"]
    assert "outputSchema" in s
    assert "path" in s
print("Batch introspection OK")
')

# bundle-script smoke test - verify bundled script --help has clean output (no debug noise on stderr)
(cd test-scripts && \
  npx elm-pages bundle-script src/TestWithSchema.elm --output ./test-bundled.mjs && \
  node ./test-bundled.mjs --help 2>/tmp/bundle-help-stderr.txt && \
  python3 -c '
with open("/tmp/bundle-help-stderr.txt") as f:
    stderr = f.read()
assert stderr.strip() == "", "Expected clean stderr from --help, got: " + repr(stderr)
print("bundle-script --help OK")
' && rm -f ./test-bundled.mjs)

# Stream tests - tests gzip, unzip, command stdin handling, etc.
(cd examples/end-to-end && npm ci && npx elm-pages run script/src/StreamTests.elm)

# File/Script utility tests - tests file operations, optional, finally, etc.
(cd examples/end-to-end && npx elm-pages run script/src/FileTests.elm)

# Multipart tests - tests multipartBody encoding via busboy round-trip
(cd examples/end-to-end && npx elm-pages run script/src/MultipartTests.elm)

# DB unit tests - tests Test.BackendTask virtual DB layer with real Pages.Db + Wire3 round-trip
(cd examples/end-to-end && npx elm-pages run script/src/DbUnitTests.elm)

# Timezone tests - tests BackendTask.Time.zone and zoneInRange with DST transitions
(cd examples/end-to-end && TZ=America/New_York npx elm-pages run script/src/TimezoneTests.elm)

# Scaffold tests - verify AddRoute with form fields generates compilable code
# Uses end-to-end example which references local src/ via source-directories
(cd examples/end-to-end && \
  npx elm-codegen install && \
  npx elm-pages run script/src/AddRoute.elm TestScaffold name:text email:text && \
  npx elm-pages gen && \
  lamdera make app/Route/TestScaffold.elm && \
  rm app/Route/TestScaffold.elm)
