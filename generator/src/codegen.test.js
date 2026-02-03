import { compareEphemeralFields, formatDisagreementError } from "./codegen.js";
import assert from "assert";

// Test: No disagreement when both agree
function testNoDisagreement() {
  const serverFields = new Map([
    ["Route.Index", new Set(["body", "content"])],
    ["Route.Blog", new Set(["title"])],
  ]);
  const clientFields = new Map([
    ["Route.Index", new Set(["body", "content"])],
    ["Route.Blog", new Set(["title"])],
  ]);

  const result = compareEphemeralFields(serverFields, clientFields);
  assert.strictEqual(result, null, "Should return null when no disagreement");
  console.log("✓ testNoDisagreement passed");
}

// Test: Detects server-only ephemeral fields
function testServerOnlyEphemeral() {
  const serverFields = new Map([
    ["Route.Index", new Set(["body", "content", "serverOnly"])],
  ]);
  const clientFields = new Map([
    ["Route.Index", new Set(["body", "content"])],
  ]);

  const result = compareEphemeralFields(serverFields, clientFields);
  assert.notStrictEqual(result, null, "Should detect disagreement");
  assert.strictEqual(result.disagreements.length, 1);
  assert.strictEqual(result.disagreements[0].module, "Route.Index");
  assert.deepStrictEqual(result.disagreements[0].serverOnly, ["serverOnly"]);
  assert.deepStrictEqual(result.disagreements[0].clientOnly, []);
  console.log("✓ testServerOnlyEphemeral passed");
}

// Test: Detects client-only ephemeral fields
function testClientOnlyEphemeral() {
  const serverFields = new Map([
    ["Route.Index", new Set(["body"])],
  ]);
  const clientFields = new Map([
    ["Route.Index", new Set(["body", "clientOnly"])],
  ]);

  const result = compareEphemeralFields(serverFields, clientFields);
  assert.notStrictEqual(result, null, "Should detect disagreement");
  assert.strictEqual(result.disagreements.length, 1);
  assert.strictEqual(result.disagreements[0].module, "Route.Index");
  assert.deepStrictEqual(result.disagreements[0].serverOnly, []);
  assert.deepStrictEqual(result.disagreements[0].clientOnly, ["clientOnly"]);
  console.log("✓ testClientOnlyEphemeral passed");
}

// Test: Detects mixed disagreements
function testMixedDisagreements() {
  const serverFields = new Map([
    ["Route.Index", new Set(["body", "serverField"])],
    ["Route.Blog", new Set(["title", "blogServerField"])],
  ]);
  const clientFields = new Map([
    ["Route.Index", new Set(["body", "clientField"])],
    ["Route.Blog", new Set(["title"])],
  ]);

  const result = compareEphemeralFields(serverFields, clientFields);
  assert.notStrictEqual(result, null, "Should detect disagreements");
  assert.strictEqual(result.disagreements.length, 2);

  // Find the Route.Index disagreement
  const indexDisagreement = result.disagreements.find(d => d.module === "Route.Index");
  assert.ok(indexDisagreement);
  assert.deepStrictEqual(indexDisagreement.serverOnly, ["serverField"]);
  assert.deepStrictEqual(indexDisagreement.clientOnly, ["clientField"]);

  // Find the Route.Blog disagreement
  const blogDisagreement = result.disagreements.find(d => d.module === "Route.Blog");
  assert.ok(blogDisagreement);
  assert.deepStrictEqual(blogDisagreement.serverOnly, ["blogServerField"]);
  assert.deepStrictEqual(blogDisagreement.clientOnly, []);

  console.log("✓ testMixedDisagreements passed");
}

// Test: Handles empty maps
function testEmptyMaps() {
  const result = compareEphemeralFields(new Map(), new Map());
  assert.strictEqual(result, null, "Should return null for empty maps");
  console.log("✓ testEmptyMaps passed");
}

// Test: Handles module only on one side
function testModuleOnlyOnOneSide() {
  const serverFields = new Map([
    ["Route.Index", new Set(["body"])],
    ["Route.ServerOnly", new Set(["field"])],
  ]);
  const clientFields = new Map([
    ["Route.Index", new Set(["body"])],
  ]);

  const result = compareEphemeralFields(serverFields, clientFields);
  assert.notStrictEqual(result, null, "Should detect disagreement");
  assert.strictEqual(result.disagreements.length, 1);
  assert.strictEqual(result.disagreements[0].module, "Route.ServerOnly");
  assert.deepStrictEqual(result.disagreements[0].serverOnly, ["field"]);
  assert.deepStrictEqual(result.disagreements[0].clientOnly, []);
  console.log("✓ testModuleOnlyOnOneSide passed");
}

// Test: formatDisagreementError produces readable output
function testFormatDisagreementError() {
  const comparison = {
    disagreements: [
      { module: "Route.Index", serverOnly: ["body", "content"], clientOnly: ["title"] },
      { module: "Route.Blog", serverOnly: [], clientOnly: ["author"] },
    ],
  };

  const output = formatDisagreementError(comparison);
  assert.ok(output.includes("EPHEMERAL FIELD DISAGREEMENT"), "Should include header");
  assert.ok(output.includes("Route.Index"), "Should include module name");
  assert.ok(output.includes('Field "body": server says ephemeral, client says persistent'), "Should explain server-only field");
  assert.ok(output.includes('Field "content": server says ephemeral, client says persistent'), "Should explain second server-only field");
  assert.ok(output.includes('Field "title": client says ephemeral, server says persistent'), "Should explain client-only field");
  assert.ok(output.includes("Route.Blog"), "Should include second module");
  assert.ok(output.includes('Field "author": client says ephemeral, server says persistent'), "Should explain second module's client-only field");
  console.log("✓ testFormatDisagreementError passed");
}

// Run all tests
console.log("Running ephemeral field comparison tests...\n");
testNoDisagreement();
testServerOnlyEphemeral();
testClientOnlyEphemeral();
testMixedDisagreements();
testEmptyMaps();
testModuleOnlyOnOneSide();
testFormatDisagreementError();
console.log("\n✅ All tests passed!");
