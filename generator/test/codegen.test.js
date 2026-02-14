/**
 * Tests for ephemeral field comparison functions in codegen.js
 */

import { describe, it, expect } from "vitest";
import { compareEphemeralFields, formatDisagreementError } from "../src/codegen.js";

describe("compareEphemeralFields", () => {
  it("returns null when both agree", () => {
    const serverFields = new Map([
      ["Route.Index", new Set(["body", "content"])],
      ["Route.Blog", new Set(["title"])],
    ]);
    const clientFields = new Map([
      ["Route.Index", new Set(["body", "content"])],
      ["Route.Blog", new Set(["title"])],
    ]);

    const result = compareEphemeralFields(serverFields, clientFields);
    expect(result).toBeNull();
  });

  it("detects server-only ephemeral fields", () => {
    const serverFields = new Map([
      ["Route.Index", new Set(["body", "content", "serverOnly"])],
    ]);
    const clientFields = new Map([
      ["Route.Index", new Set(["body", "content"])],
    ]);

    const result = compareEphemeralFields(serverFields, clientFields);
    expect(result).not.toBeNull();
    expect(result.disagreements).toHaveLength(1);
    expect(result.disagreements[0].module).toBe("Route.Index");
    expect(result.disagreements[0].serverOnly).toEqual(["serverOnly"]);
    expect(result.disagreements[0].clientOnly).toEqual([]);
  });

  it("detects client-only ephemeral fields", () => {
    const serverFields = new Map([
      ["Route.Index", new Set(["body"])],
    ]);
    const clientFields = new Map([
      ["Route.Index", new Set(["body", "clientOnly"])],
    ]);

    const result = compareEphemeralFields(serverFields, clientFields);
    expect(result).not.toBeNull();
    expect(result.disagreements).toHaveLength(1);
    expect(result.disagreements[0].module).toBe("Route.Index");
    expect(result.disagreements[0].serverOnly).toEqual([]);
    expect(result.disagreements[0].clientOnly).toEqual(["clientOnly"]);
  });

  it("detects mixed disagreements across modules", () => {
    const serverFields = new Map([
      ["Route.Index", new Set(["body", "serverField"])],
      ["Route.Blog", new Set(["title", "blogServerField"])],
    ]);
    const clientFields = new Map([
      ["Route.Index", new Set(["body", "clientField"])],
      ["Route.Blog", new Set(["title"])],
    ]);

    const result = compareEphemeralFields(serverFields, clientFields);
    expect(result).not.toBeNull();
    expect(result.disagreements).toHaveLength(2);

    const indexDisagreement = result.disagreements.find(d => d.module === "Route.Index");
    expect(indexDisagreement).toBeDefined();
    expect(indexDisagreement.serverOnly).toEqual(["serverField"]);
    expect(indexDisagreement.clientOnly).toEqual(["clientField"]);

    const blogDisagreement = result.disagreements.find(d => d.module === "Route.Blog");
    expect(blogDisagreement).toBeDefined();
    expect(blogDisagreement.serverOnly).toEqual(["blogServerField"]);
    expect(blogDisagreement.clientOnly).toEqual([]);
  });

  it("returns null for empty maps", () => {
    const result = compareEphemeralFields(new Map(), new Map());
    expect(result).toBeNull();
  });

  it("handles module only present on one side", () => {
    const serverFields = new Map([
      ["Route.Index", new Set(["body"])],
      ["Route.ServerOnly", new Set(["field"])],
    ]);
    const clientFields = new Map([
      ["Route.Index", new Set(["body"])],
    ]);

    const result = compareEphemeralFields(serverFields, clientFields);
    expect(result).not.toBeNull();
    expect(result.disagreements).toHaveLength(1);
    expect(result.disagreements[0].module).toBe("Route.ServerOnly");
    expect(result.disagreements[0].serverOnly).toEqual(["field"]);
    expect(result.disagreements[0].clientOnly).toEqual([]);
  });
});

describe("formatDisagreementError", () => {
  it("produces readable output", () => {
    const comparison = {
      disagreements: [
        { module: "Route.Index", serverOnly: ["body", "content"], clientOnly: ["title"] },
        { module: "Route.Blog", serverOnly: [], clientOnly: ["author"] },
      ],
    };

    const output = formatDisagreementError(comparison);
    expect(output).toContain("EPHEMERAL FIELD DISAGREEMENT");
    expect(output).toContain("Route.Index");
    expect(output).toContain('Field "body": server says ephemeral, client says persistent');
    expect(output).toContain('Field "content": server says ephemeral, client says persistent');
    expect(output).toContain('Field "title": client says ephemeral, server says persistent');
    expect(output).toContain("Route.Blog");
    expect(output).toContain('Field "author": client says ephemeral, server says persistent');
  });
});
