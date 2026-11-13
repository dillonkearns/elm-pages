// Hot reloading in the dev server: editing an Elm file swaps the new code into
// the running page, without a page reload and without losing the app's state.

const counterRoute = "app/Route/Counter.elm";

context("dev server hot reloading", () => {
  let originalSource;

  before(() => {
    cy.readFile(counterRoute).then((source) => {
      originalSource = source;
    });
  });

  after(() => {
    // Put the file back even if the test failed halfway.
    cy.writeFile(counterRoute, originalSource);
  });

  it("applies a code change and keeps the page's state", () => {
    cy.visit("/counter");
    cy.contains("Count: 0");
    cy.contains("button", "+").click();
    cy.contains("Count: 1");
    cy.contains("button", "+").click();
    cy.contains("Count: 2");
    // A full page reload would wipe this out.
    cy.window().then((win) => {
      win.stillTheSamePage = true;
    });

    cy.then(() => {
      expect(originalSource).to.include('"Count: "');
      cy.writeFile(counterRoute, originalSource.replace('"Count: "', '"Total: "'));
    });

    // New view code, same model.
    cy.contains("Total: 2");
    cy.window().its("stillTheSamePage").should("equal", true);

    // The app still responds to events after the swap.
    cy.contains("button", "+").click();
    cy.contains("Total: 3");
  });
});
