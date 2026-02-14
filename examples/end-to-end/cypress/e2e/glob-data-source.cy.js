it(`glob tests`, () => {
    cy.visit("/tests");
    cy.get(".test-pass").should("exist");
    cy.get(".test-fail").should("not.exist");
});
export {};
