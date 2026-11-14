// The app's first render must match the HTML that the server sent, so that the
// app takes over the page that is already there instead of building it again.

import {
  recordRemovedElements,
  recordTitles,
  rememberServerElements,
} from "../support/first-render.js";

function watchTheAppStart(win) {
  recordTitles(win);
  recordRemovedElements(win);
  rememberServerElements(win);
}

function serverElementsAreStillOnThePage() {
  cy.window().then((win) => {
    expect(win.serverElements.length).to.be.greaterThan(5);
    const missing = win.serverElements
      .filter((element) => !win.document.body.contains(element))
      .map((element) => element.outerHTML.slice(0, 200));
    expect(missing, "server elements that are gone").to.deep.equal([]);
    expect(win.removedElements, "removed elements").to.deep.equal([]);
  });
}

context("first render in a production build", () => {
  it("keeps the server-rendered page, frozen view included", () => {
    cy.visit("/static-region-test", { onBeforeLoad: watchTheAppStart });
    cy.window().then((win) => {
      win.serverFrozenView = win.serverElements.find((element) =>
        element.matches('[data-static="0"]')
      );
      expect(
        win.serverFrozenView instanceof win.Element,
        "the server sent the frozen view"
      ).to.equal(true);
    });

    // The app is running.
    cy.contains("Counter: 0");
    cy.contains("button", "+").click();
    cy.contains("Counter: 1");

    serverElementsAreStillOnThePage();
    cy.window().then((win) => {
      expect(
        win.document.querySelector('[data-static="0"]') === win.serverFrozenView,
        "the frozen view is the element the server sent"
      ).to.equal(true);
    });
    cy.window().its("titlesSet").should("not.include", "Page Data Error");
  });

  it("keeps the server-rendered page on a page without frozen views", () => {
    cy.visit("/", { onBeforeLoad: watchTheAppStart });
    cy.contains("This is the index page.");
    cy.get("[data-url]").should(($element) => {
      expect($element.attr("data-url")).to.include("localhost");
    });

    serverElementsAreStillOnThePage();
    cy.window().its("titlesSet").should("not.include", "Page Data Error");
  });
});
