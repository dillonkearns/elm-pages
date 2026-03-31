context("SetField effect", () => {
  it("programmatically sets a form field value", () => {
    cy.visit("/set-field");
    cy.get('[data-testid="name-input"]').should("have.value", "");
    cy.get('[data-testid="set-field-button"]').click();
    cy.get('[data-testid="name-input"]').should("have.value", "Suggested Value");
  });
});
