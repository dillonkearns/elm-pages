// Frozen views (`View.freeze`) in a production build.
//
// In a production build the frozen content is left out of the client bundle
// (see check-frozen-views.mjs), so the browser has to draw it from the
// server-rendered HTML: when the app starts, and again when you come back to
// the page with client-side navigation.

const frozenText = "Frozen view code: this text must not be in the client bundle.";
const frozenDataText = "Frozen data: this text must not be in the client bundle.";

/** Collect uncaught errors, so the test can check that there were none. */
function watchForErrors(win) {
  win.pageErrors = [];
  win.addEventListener("error", (event) =>
    win.pageErrors.push(String(event.message))
  );
}

function frozenViewIsShown() {
  cy.get('[data-static="0"]')
    .should("contain", frozenText)
    .and("contain", frozenDataText)
    .and("contain", "Item 3 - never re-rendered on client");
}

context("frozen views in a production build", () => {
  it("shows the frozen view once the app has started", () => {
    cy.visit("/static-region-test", { onBeforeLoad: watchForErrors });
    frozenViewIsShown();

    // The app is running: the dynamic part of the page responds...
    cy.contains("Counter: 0");
    cy.contains("button", "+").click();
    cy.contains("button", "+").click();
    cy.contains("Counter: 2");

    // ...and the frozen view is still there after those re-renders.
    frozenViewIsShown();
    cy.get('[data-static="0"]').should("have.length", 1);
    cy.window().its("pageErrors").should("deep.equal", []);
  });

  it("shows the frozen view again after navigating away and back", () => {
    cy.visit("/static-region-test", { onBeforeLoad: watchForErrors });
    frozenViewIsShown();
    cy.window().then((win) => {
      win.stillTheSamePage = true;
    });

    cy.contains("a", "index page").click();
    cy.contains("This is the index page.");
    cy.get('[data-static="0"]').should("not.exist");
    cy.contains(frozenText).should("not.exist");

    cy.go("back");
    cy.location("pathname").should("include", "/static-region-test");
    frozenViewIsShown();
    cy.contains("Counter: 0");
    cy.contains("button", "+").click();
    cy.contains("Counter: 1");

    // All of that was client-side navigation, with no errors.
    cy.window().its("stillTheSamePage").should("equal", true);
    cy.window().its("pageErrors").should("deep.equal", []);
  });
});
