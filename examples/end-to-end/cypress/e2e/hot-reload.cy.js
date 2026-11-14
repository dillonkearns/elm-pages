// Hot reloading in the dev server: editing an Elm file swaps the new code into
// the running page, without a page reload and without losing the app's state.
//
// This spec runs twice in CI: against `elm-pages dev --debug` (with the rest of
// cypress/e2e) and against plain `elm-pages dev` (cypress.dev-default.config.js).

const counterRoute = "app/Route/Counter.elm";

/** @type {string} */
let originalSource;

/**
 * Save a changed copy of the Counter route, which makes the dev server
 * compile it and send the new code to the page.
 *
 * @param {[string, string][]} replacements - pairs of [text to find, text to put there]
 */
function editCounterRoute(replacements) {
  cy.then(() => {
    let source = originalSource;
    for (const [from, to] of replacements) {
      expect(source, `Counter.elm should contain ${from}`).to.include(from);
      source = source.replace(from, to);
    }
    cy.writeFile(counterRoute, source);
  });
}

/** Click "+" until the page shows the given count, checking each step. */
function countUpTo(count, label = "Count") {
  for (let i = 1; i <= count; i++) {
    cy.contains("button", "+").click();
    cy.contains(`${label}: ${i}`);
  }
}

/**
 * Leave marks that only survive if the page is not loaded again and the
 * heading is not drawn again from scratch.
 */
function markThePage() {
  cy.window().then((win) => {
    win.stillTheSamePage = true;
  });
  cy.get("h1").then(($heading) => {
    $heading[0].stillTheSameElement = true;
  });
}

function pageWasNotReloaded() {
  cy.window().its("stillTheSamePage").should("equal", true);
  cy.get("h1").its("0.stillTheSameElement").should("equal", true);
  cy.get("@consoleError").should(
    "not.have.been.calledWithMatch",
    /Could not hot reload/
  );
}

function errorOverlay() {
  return cy.get("[id='elm-live:elmErrorContainer']");
}

context("dev server hot reloading", () => {
  before(() => {
    cy.readFile(counterRoute).then((source) => {
      originalSource = source;
    });
  });

  beforeEach(() => {
    cy.visit("/counter", {
      onBeforeLoad(win) {
        cy.spy(win.console, "error").as("consoleError");
      },
    });
    cy.contains("Count: 0");
  });

  afterEach(() => {
    // Put the file back even if the test failed halfway, and wait until the
    // dev server has compiled it, so the next test starts from a quiet server.
    cy.writeFile(counterRoute, originalSource);
    cy.contains("Count: ");
    errorOverlay().should("not.exist");
  });

  it("applies a change to the view and keeps the page's state", () => {
    countUpTo(2);
    markThePage();

    editCounterRoute([['"Count: "', '"Total: "']]);

    // New view code, same model.
    cy.contains("Total: 2");
    pageWasNotReloaded();

    // The app still responds to events after the swap.
    cy.contains("button", "+").click();
    cy.contains("Total: 3");
  });

  it("applies a change to update and keeps the page's state", () => {
    countUpTo(2);
    markThePage();

    editCounterRoute([
      ["model.count + 1", "model.count + 10"],
      ['Html.text "Counter"', 'Html.text "Counter by tens"'],
    ]);

    // The heading tells us the new code has arrived.
    cy.contains("h1", "Counter by tens");
    cy.contains("Count: 2");
    cy.contains("button", "+").click();
    cy.contains("Count: 12");
    pageWasNotReloaded();
  });

  it("keeps the state through several changes in a row", () => {
    countUpTo(2);
    markThePage();

    editCounterRoute([['"Count: "', '"Total: "']]);
    cy.contains("Total: 2");
    cy.contains("button", "+").click();
    cy.contains("Total: 3");

    editCounterRoute([['"Count: "', '"Sum: "']]);
    cy.contains("Sum: 3");
    cy.contains("button", "+").click();
    cy.contains("Sum: 4");

    editCounterRoute([['"Count: "', '"Clicks: "']]);
    cy.contains("Clicks: 4");
    pageWasNotReloaded();
  });

  it("shows a compiler error, then keeps the state once it is fixed", () => {
    countUpTo(2);
    markThePage();

    // `model.count` is an Int, so this does not compile.
    editCounterRoute([["String.fromInt model.count", "model.count"]]);
    errorOverlay().should("contain.text", "TYPE MISMATCH");

    editCounterRoute([['"Count: "', '"Total: "']]);
    cy.contains("Total: 2");
    errorOverlay().should("not.exist");
    pageWasNotReloaded();

    cy.contains("button", "+").click();
    cy.contains("Total: 3");
  });
});
