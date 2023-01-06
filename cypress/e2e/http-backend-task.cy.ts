it(`BackendTask tests`, () => {
  cy.visit("/http-tests");
  cy.get(".test-pass").should("exist");
  cy.get(".test-fail").should("not.exist");
});
