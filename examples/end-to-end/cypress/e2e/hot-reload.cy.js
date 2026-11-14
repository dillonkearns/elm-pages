// Hot reloading in the dev server: editing an Elm file swaps the new code into
// the running page, without a page reload and without losing the app's state.
//
// This spec runs twice in CI: against `elm-pages dev --debug` (with the rest of
// cypress/e2e) and against plain `elm-pages dev` (cypress.dev-default.config.js).

const counterRoute = "app/Route/Counter.elm";
const sharedModule = "app/Shared.elm";

/**
 * The files these tests change, as they were before the tests ran.
 *
 * @type {Record<string, string>}
 */
const originalSources = {};

/**
 * Save a changed copy of an Elm file, which makes the dev server compile it
 * and send the new code to the page.
 *
 * @param {string} file
 * @param {[string, string][]} replacements - pairs of [text to find, text to put there]
 */
function editFile(file, replacements) {
  cy.then(() => {
    let source = originalSources[file];
    for (const [from, to] of replacements) {
      expect(source, `${file} should contain ${from}`).to.include(from);
      source = source.replace(from, to);
    }
    cy.writeFile(file, source);
  });
}

/** @param {[string, string][]} replacements */
function editCounterRoute(replacements) {
  editFile(counterRoute, replacements);
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

function pageMarkIsGone() {
  cy.window().should((win) => {
    expect(win.stillTheSamePage).to.equal(undefined);
  });
}

/**
 * The page was loaded again: the marks are gone and the app started over,
 * with a fresh model.
 */
function pageWasReloaded() {
  cy.contains("Count: 0");
  pageMarkIsGone();
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
    for (const file of [counterRoute, sharedModule]) {
      cy.readFile(file).then((source) => {
        originalSources[file] = source;
      });
    }
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
    for (const file of [counterRoute, sharedModule]) {
      cy.readFile(file).then((source) => {
        if (source !== originalSources[file]) {
          cy.writeFile(file, originalSources[file]);
        }
      });
    }
    cy.contains("h1", /^Counter$/);
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

  // New code cannot run on a model that was made by code with different types.
  // So when the types the app keeps in memory change, the page is loaded again
  // and the app starts over, instead of running with a model that does not fit.
  describe("when the app's types change", () => {
    it("reloads the page when a field is added to the route's Model", () => {
      countUpTo(2);
      markThePage();

      editCounterRoute([
        ["{ count : Int\n    }", "{ count : Int\n    , step : Int\n    }"],
        ["{ count = 0 }", "{ count = 0, step = 5 }"],
        ["model.count + 1", "model.count + model.step"],
        ['Html.text "Counter"', 'Html.text "Counter with steps"'],
      ]);

      cy.contains("h1", "Counter with steps");
      pageWasReloaded();

      // The new field is there, so the new code works.
      cy.contains("button", "+").click();
      cy.contains("Count: 5");
    });

    it("reloads the page when a variant is added to the route's Msg", () => {
      countUpTo(2);
      markThePage();

      editCounterRoute([
        ["    | Reset\n", "    | Reset\n    | Double\n"],
        [
          "        Reset ->\n",
          "        Double ->\n            ( { model | count = model.count * 2 }, Effect.none )\n\n        Reset ->\n",
        ],
        [
          '[ Html.text "Reset" ]',
          '[ Html.text "Reset" ]\n            , Html.button\n                [ Events.onClick (PagesMsg.fromMsg Double) ]\n                [ Html.text "Double" ]',
        ],
      ]);

      cy.contains("button", "Double");
      pageWasReloaded();

      countUpTo(3);
      cy.contains("button", "Double").click();
      cy.contains("Count: 6");
    });

    it("reloads the page when a field is added to Shared.Model", () => {
      countUpTo(2);
      markThePage();

      editFile(sharedModule, [
        [
          "{ showMobileMenu : Bool\n    }",
          "{ showMobileMenu : Bool\n    , visits : Int\n    }",
        ],
        ["{ showMobileMenu = False }", "{ showMobileMenu = False, visits = 0 }"],
      ]);

      pageWasReloaded();
      countUpTo(1);
    });

    it("reloads the page when the route's Data changes", () => {
      countUpTo(2);
      markThePage();

      editCounterRoute([
        ["type alias Data =\n    {}", "type alias Data =\n    { label : String }"],
        ["BackendTask.succeed Data", 'BackendTask.succeed (Data "Clicks")'],
        ['"Count: "', 'app.data.label ++ ": "'],
      ]);

      cy.contains("Clicks: 0");
      pageMarkIsGone();
      cy.contains("button", "+").click();
      cy.contains("Clicks: 1");
    });
  });
});
