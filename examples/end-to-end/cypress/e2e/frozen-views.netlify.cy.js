function parseFrozenViewsFromBinary(binaryBody) {
  const buffer = Cypress.Buffer.from(binaryBody, "binary");
  const jsonLength = buffer.readUInt32BE(0);
  const jsonString = buffer.subarray(4, 4 + jsonLength).toString("utf8");
  return JSON.parse(jsonString);
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

  it("serves frozen HTML payload from content.dat", () => {
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

      expect(Object.keys(frozenViews)).to.have.length(3);
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
    });
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
