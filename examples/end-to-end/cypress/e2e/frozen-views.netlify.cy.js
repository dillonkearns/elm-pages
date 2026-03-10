function parseFrozenViewsFromBinary(binaryBody) {
  const buffer = Cypress.Buffer.from(binaryBody, "binary");
  const jsonLength = buffer.readUInt32BE(0);
  const jsonString = buffer.subarray(4, 4 + jsonLength).toString("utf8");
  return JSON.parse(jsonString);
}

function extractDataStaticIds(html) {
  const ids = new Set();
  const pattern = /data-static="([^"]+)"/g;
  let match = pattern.exec(html);

  while (match !== null) {
    ids.add(match[1]);
    match = pattern.exec(html);
  }

  return [...ids].sort();
}

context("frozen views netlify build output", () => {
  it("navigates to frozen views from the index page", () => {
    cy.visit("/");
    cy.contains("a", "Frozen Views (Netlify)").click();
    cy.url().should("include", "/frozen-views");
    cy.contains("h1", "Frozen Views (Netlify E2E)");
    cy.contains("h3", "Live Server Data");
    cy.contains("Transitive helper card A");
    cy.contains("Transitive helper card B");
  });

  it("serves frozen HTML payload from content.dat with all helper patterns", () => {
    cy.request({
      url: "/frozen-views/content.dat?name=codex",
      encoding: "binary",
      headers: {
        "accept-language": "en-US,en;q=0.9",
      },
    }).then((response) => {
      expect(response.status).to.eq(200);
      expect(response.headers["content-type"]).to.include(
        "application/octet-stream"
      );

      const frozenViews = parseFrozenViewsFromBinary(response.body);
      const html = Object.values(frozenViews).join("\n");
      const frozenViewCount = Object.keys(frozenViews).length;

      // Original patterns: 1 direct freeze + 2 transitive helpers
      expect(html).to.include("Live Server Data");
      expect(html).to.include("Name from query params: codex");
      expect(html).to.include("Language Preferences: en-US");
      expect(html).to.include("Transitive helper card A");
      expect(html).to.include("Transitive helper card B");
      expect(html).to.include(
        "Route -&gt; wrapper -&gt; freeze helper (first call site)"
      );
      expect(html).to.include(
        "Route -&gt; wrapper -&gt; freeze helper (second call site)"
      );

      // Cross-module helper with String first arg (FID param + String arg seeding)
      expect(html).to.include("e2e-alpha");
      expect(html).to.include("e2e-beta");

      // Forward-referenced route-local helper with String first arg
      expect(html).to.include("Local Helper Card");
      expect(html).to.include("Second Local Card");
      expect(html).to.include(
        "Route-local helper with String arg, defined after view"
      );

      // Frozen helper badge called from Shared.elm (shared-scoped seeding)
      expect(html).to.include("shared-e2e");

      // Total: 1 direct + 2 transitive + 2 badge + 2 localInfoCard + 1 shared badge = 8
      expect(frozenViewCount).to.eq(8);
    });
  });

  it("matches content.dat frozen view keys to server-rendered data-static ids", () => {
    cy.request({
      url: "/frozen-views/content.dat?name=codex",
      encoding: "binary",
      headers: {
        "accept-language": "en-US,en;q=0.9",
      },
    }).then((contentDatResponse) => {
      const frozenViews = parseFrozenViewsFromBinary(contentDatResponse.body);
      const contentDatKeys = Object.keys(frozenViews).sort();

      cy.request("/frozen-views?name=codex").then((htmlResponse) => {
        const serverRenderedIds = extractDataStaticIds(htmlResponse.body);
        expect(contentDatKeys).to.deep.equal(serverRenderedIds);
      });
    });
  });

  it("renders cross-module String-arg badge helper content on the page", () => {
    cy.visit("/frozen-views");
    cy.contains("e2e-alpha");
    cy.contains("e2e-beta");
  });

  it("renders forward-referenced route-local helper content on the page", () => {
    cy.visit("/frozen-views");
    cy.contains("Local Helper Card");
    cy.contains("Second Local Card");
  });

  it("renders shared-scoped frozen helper badge on the page", () => {
    cy.visit("/frozen-views");
    cy.contains("shared-e2e");
  });

  it("keeps interactive islands working", () => {
    cy.visit("/frozen-views");
    cy.contains("h3", "Interactive Counter (Island)")
      .parent()
      .within(() => {
        cy.contains("Counter: 0");
        cy.contains("button", "+").click();
        cy.contains("Counter: 1");
      });
  });
});
