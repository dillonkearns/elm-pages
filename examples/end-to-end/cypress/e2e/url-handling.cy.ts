context("url handling", () => {
  it("does not reload page when clicking a link to current page", () => {
    cy.visit("/");
    cy.window().then((win) => 
    // set some state on the window. If this property is cleared then
    // we know the page reloaded.
      (win.thisWasNotReloaded = true));
    cy.window().should('have.prop', 'thisWasNotReloaded');
    cy.contains("Link to Self").click()
    cy.contains("Link to Self")
    cy.window().should('have.prop', 'thisWasNotReloaded');
  });
});
