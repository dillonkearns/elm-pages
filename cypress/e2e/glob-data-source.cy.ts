it(`glob tests`, () => {
  cy.visit("/tests");
  cy.contains("All tests passed");
  cy.document().should("not.include.text", "Expected");
});
