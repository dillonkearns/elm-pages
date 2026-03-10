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

      // Color palette inside View.freeze (tests DCE of elm-color-extra)
      expect(html).to.include("Frozen Color Palette (DCE Test)");
      expect(html).to.include("Generated from seed: codex");
      // Verify actual color hex values are rendered (from Color.Convert.colorToHex)
      expect(html).to.match(/#[0-9a-fA-F]{6}/);

      // Total: 1 direct + 1 colorPalette + 2 transitive + 2 badge + 2 localInfoCard + 1 shared badge = 9
      expect(frozenViewCount).to.eq(9);
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

  it("renders frozen color palette with DCE'd elm-color-extra content", () => {
    cy.visit("/frozen-views?name=codex");
    cy.contains("h3", "Frozen Color Palette (DCE Test)");
    cy.contains("Generated from seed: codex");
    cy.contains("Base");
    cy.contains("Lighter");
    cy.contains("Darker");
    cy.contains("Complement");
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

  it("preserves frozen views after SPA navigation away and back", () => {
    // Start on frozen views page via full page load
    cy.visit("/frozen-views");
    cy.contains("h1", "Frozen Views (Netlify E2E)");
    cy.contains("Transitive helper card A");

    // SPA navigate to index via back link
    cy.contains("a", "Back to Index").click();
    cy.url().should("not.include", "/frozen-views");
    cy.contains("This is the index page.");

    // SPA navigate back to frozen views
    cy.contains("a", "Frozen Views (Netlify)").click();
    cy.url().should("include", "/frozen-views");

    // Verify frozen content still renders after SPA transition
    cy.contains("h1", "Frozen Views (Netlify E2E)");
    cy.contains("Transitive helper card A");
    cy.contains("Transitive helper card B");
    cy.contains("e2e-alpha");
    cy.contains("Local Helper Card");
    cy.contains("shared-e2e");
    cy.contains("Frozen Color Palette (DCE Test)");
  });

  it("preserves frozen views after browser back/forward navigation", () => {
    cy.visit("/frozen-views");
    cy.contains("h1", "Frozen Views (Netlify E2E)");

    // Increment counter to create local state
    cy.contains("h3", "Interactive Counter (Island)")
      .parent()
      .within(() => {
        cy.contains("button", "+").click();
        cy.contains("button", "+").click();
        cy.contains("Counter: 2");
      });

    // SPA navigate away
    cy.contains("a", "Back to Index").click();
    cy.contains("This is the index page.");

    // Browser back button
    cy.go("back");
    cy.url().should("include", "/frozen-views");

    // Frozen content should render correctly after back navigation
    cy.contains("h1", "Frozen Views (Netlify E2E)");
    cy.contains("Transitive helper card A");
    cy.contains("e2e-alpha");
    cy.contains("Frozen Color Palette (DCE Test)");

    // Browser forward button
    cy.go("forward");
    cy.url().should("not.include", "/frozen-views");
    cy.contains("This is the index page.");

    // Browser back again - frozen views should still work
    cy.go("back");
    cy.contains("h1", "Frozen Views (Netlify E2E)");
    cy.contains("Transitive helper card A");
  });
});
