context("dev server with base path", () => {
  it("submits a form to receive ActionData", () => {
    cy.visit("/get-form");
    cy.contains("Page 2").click();
    cy.contains("Current page: 2");
    cy.contains("Page 1").click();
    cy.contains("Current page: 1");
    cy.contains("Page 2").click();
    cy.contains("Current page: 2");
  });
});
