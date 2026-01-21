import { describe, it } from "node:test";
import assert from "node:assert";
import { extractStaticRegions } from "../src/extract-static-regions.js";

describe("extractStaticRegions", () => {
  it("extracts a simple static region", () => {
    const html = `
      <div>
        <div data-static="test-id">
          <p>Hello World</p>
        </div>
      </div>
    `;

    const regions = extractStaticRegions(html);

    assert.deepStrictEqual(Object.keys(regions), ["test-id"]);
    assert(regions["test-id"].includes("<p>Hello World</p>"));
    assert(regions["test-id"].startsWith('<div data-static="test-id">'));
    assert(regions["test-id"].endsWith("</div>"));
  });

  it("extracts multiple static regions", () => {
    const html = `
      <div>
        <div data-static="region-1">Content 1</div>
        <div data-static="region-2">Content 2</div>
      </div>
    `;

    const regions = extractStaticRegions(html);

    assert.deepStrictEqual(Object.keys(regions).sort(), [
      "region-1",
      "region-2",
    ]);
    assert(regions["region-1"].includes("Content 1"));
    assert(regions["region-2"].includes("Content 2"));
  });

  it("handles nested elements of the same tag", () => {
    const html = `
      <div data-static="outer">
        <div>
          <div>Nested content</div>
        </div>
      </div>
    `;

    const regions = extractStaticRegions(html);

    assert.deepStrictEqual(Object.keys(regions), ["outer"]);
    assert(regions["outer"].includes("Nested content"));
    assert(regions["outer"].endsWith("</div>"));
  });

  it("handles different tag names", () => {
    const html = `
      <section data-static="my-section">
        <p>Section content</p>
      </section>
    `;

    const regions = extractStaticRegions(html);

    assert.deepStrictEqual(Object.keys(regions), ["my-section"]);
    assert(regions["my-section"].startsWith('<section data-static="my-section">'));
    assert(regions["my-section"].endsWith("</section>"));
  });

  it("returns empty object when no static regions", () => {
    const html = `<div><p>No static regions here</p></div>`;

    const regions = extractStaticRegions(html);

    assert.deepStrictEqual(regions, {});
  });

  it("handles attributes before data-static", () => {
    const html = `<div class="foo" data-static="test">Content</div>`;

    const regions = extractStaticRegions(html);

    assert.deepStrictEqual(Object.keys(regions), ["test"]);
  });

  it("handles attributes after data-static", () => {
    const html = `<div data-static="test" class="foo">Content</div>`;

    const regions = extractStaticRegions(html);

    assert.deepStrictEqual(Object.keys(regions), ["test"]);
  });
});

