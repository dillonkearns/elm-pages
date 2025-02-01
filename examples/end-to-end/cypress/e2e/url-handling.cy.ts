context("url handling", () => {
  it("does not reload page when clicking a link to current page", () => {
    cy.visit("/");
    cy.window().then(
      (win) =>
        // set some state on the window. If this property is cleared then
        // we know the page reloaded.
        (win.thisWasNotReloaded = true)
    );
    cy.window().should("have.prop", "thisWasNotReloaded");
    cy.contains("Link to Self").click();
    cy.contains("Link to Self");
    cy.window().should("have.prop", "thisWasNotReloaded");
  });
  it("scrolls to named anchor when clicking links with hash with no page reloads", () => {
    cy.visit("/hashes");
    cy.window().then(
      (win) =>
        // set some state on the window. If this property is cleared then
        // we know the page reloaded.
        (win.thisWasNotReloaded = true)
    );
    cy.window().should("have.prop", "thisWasNotReloaded");
    cy.url().should("eq", "http://localhost:1234/hashes");
    cy.get("#a a").click();
    cy.url().should("include", "hashes#a");
    cy.get("#d a").click();
    cy.url().should("include", "hashes#d");
    cy.window().its("scrollY").should("not.equal", 0);
    cy.contains("Top of the page").click();
    cy.url().should("eq", "http://localhost:1234/hashes");
    cy.window().its("scrollY").should("equal", 0);
    cy.window().should("have.prop", "thisWasNotReloaded");
  });
});
