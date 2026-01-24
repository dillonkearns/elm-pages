import { describe, it, expect } from "vitest";
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

    expect(Object.keys(regions)).toEqual(["test-id"]);
    expect(regions["test-id"]).toContain("<p>Hello World</p>");
    expect(regions["test-id"].startsWith('<div data-static="test-id">')).toBe(true);
    expect(regions["test-id"].endsWith("</div>")).toBe(true);
  });

  it("extracts multiple static regions", () => {
    const html = `
      <div>
        <div data-static="region-1">Content 1</div>
        <div data-static="region-2">Content 2</div>
      </div>
    `;

    const regions = extractStaticRegions(html);

    expect(Object.keys(regions).sort()).toEqual([
      "region-1",
      "region-2",
    ]);
    expect(regions["region-1"]).toContain("Content 1");
    expect(regions["region-2"]).toContain("Content 2");
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

    expect(Object.keys(regions)).toEqual(["outer"]);
    expect(regions["outer"]).toContain("Nested content");
    expect(regions["outer"].endsWith("</div>")).toBe(true);
  });

  it("handles different tag names", () => {
    const html = `
      <section data-static="my-section">
        <p>Section content</p>
      </section>
    `;

    const regions = extractStaticRegions(html);

    expect(Object.keys(regions)).toEqual(["my-section"]);
    expect(regions["my-section"].startsWith('<section data-static="my-section">')).toBe(true);
    expect(regions["my-section"].endsWith("</section>")).toBe(true);
  });

  it("returns empty object when no static regions", () => {
    const html = `<div><p>No static regions here</p></div>`;

    const regions = extractStaticRegions(html);

    expect(regions).toEqual({});
  });

  it("handles attributes before data-static", () => {
    const html = `<div class="foo" data-static="test">Content</div>`;

    const regions = extractStaticRegions(html);

    expect(Object.keys(regions)).toEqual(["test"]);
  });

  it("handles attributes after data-static", () => {
    const html = `<div data-static="test" class="foo">Content</div>`;

    const regions = extractStaticRegions(html);

    expect(Object.keys(regions)).toEqual(["test"]);
  });
});
