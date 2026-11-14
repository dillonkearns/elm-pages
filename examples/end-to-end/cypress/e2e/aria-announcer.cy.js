// After client-side navigation, the page that was navigated to is announced
// to screen readers.

context("navigation announcement", () => {
  it("announces the title of the page that was navigated to", () => {
    cy.visit("/static-region-test");
    cy.contains("Counter: 0");

    cy.contains("a", "index page").click();
    cy.contains("This is the index page.");

    cy.title().should("equal", "Index page");
    cy.get("#elm-pages-announcer").should("have.text", "Navigated to Index page");
  });
});
