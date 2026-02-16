import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fetchContentWithFrozenViews } from "../static-code/frozen-views-client.js";

/**
 * @param {Record<string, string>} frozenViews
 * @param {number[]} pageDataBytes
 * @returns {ArrayBuffer}
 */
function buildContentDatBuffer(frozenViews, pageDataBytes) {
  const frozenViewsJson = JSON.stringify(frozenViews);
  const frozenViewsBytes = new TextEncoder().encode(frozenViewsJson);
  const lengthPrefix = new Uint8Array(4);
  new DataView(lengthPrefix.buffer).setUint32(0, frozenViewsBytes.length, false);

  const pageData = Uint8Array.from(pageDataBytes);
  const combined = new Uint8Array(
    lengthPrefix.length + frozenViewsBytes.length + pageData.length
  );
  combined.set(lengthPrefix, 0);
  combined.set(frozenViewsBytes, lengthPrefix.length);
  combined.set(pageData, lengthPrefix.length + frozenViewsBytes.length);
  return combined.buffer;
}

/**
 * @param {number} status
 * @param {ArrayBuffer} buffer
 */
function mockFetchResponse(status, buffer) {
  return {
    status,
    arrayBuffer: async () => buffer,
  };
}

describe("fetchContentWithFrozenViews", () => {
  beforeEach(() => {
    global.window = {
      location: { origin: "https://example.com" },
      __ELM_PAGES_FROZEN_VIEWS__: {},
    };
    global.fetch = vi.fn();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    delete global.fetch;
    delete global.window;
  });

  it("uses explicit GET method with query string", async () => {
    const buffer = buildContentDatBuffer({ hero: "<div>Hero</div>" }, [1, 2, 3]);
    global.fetch.mockResolvedValue(mockFetchResponse(200, buffer));

    const result = await fetchContentWithFrozenViews("/docs", "page=2", {
      method: "GET",
      body: null,
    });

    expect(global.fetch).toHaveBeenCalledWith(
      "https://example.com/docs/content.dat?page=2",
      { method: "GET" }
    );
    expect(result).not.toBeNull();
    expect(window.__ELM_PAGES_FROZEN_VIEWS__).toEqual({ hero: "<div>Hero</div>" });
  });

  it("uses explicit POST method even when body is empty", async () => {
    const buffer = buildContentDatBuffer({ form: "<form></form>" }, [5, 6]);
    global.fetch.mockResolvedValue(mockFetchResponse(200, buffer));

    const result = await fetchContentWithFrozenViews("/submit", null, {
      method: "POST",
      body: "",
    });

    expect(global.fetch).toHaveBeenCalledWith(
      "https://example.com/submit/content.dat/",
      {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: "",
      }
    );
    expect(result).not.toBeNull();
  });

  it("parses valid content.dat payloads even on non-2xx status", async () => {
    const buffer = buildContentDatBuffer({ notFound: "<h1>404</h1>" }, [9, 9, 9]);
    global.fetch.mockResolvedValue(mockFetchResponse(404, buffer));

    const result = await fetchContentWithFrozenViews("/missing", null, {
      method: "GET",
    });

    expect(result).not.toBeNull();
    expect(window.__ELM_PAGES_FROZEN_VIEWS__).toEqual({ notFound: "<h1>404</h1>" });
  });
});

