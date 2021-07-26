context("dev server with base path", () => {
  it("navigating with a link successfully resolves data sources", () => {
    cy.visit("/links");
    cy.contains("Root page").click();
    cy.contains("This is the index page.");
  });
});
