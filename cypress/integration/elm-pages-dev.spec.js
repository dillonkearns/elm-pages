context("dev server 404 page", () => {
  beforeEach(() => {
    cy.visit("http://localhost:1234/asdf", { failOnStatusCode: false });
  });

  it("page not found", () => {
    cy.contains("Page not found");
  });
});
