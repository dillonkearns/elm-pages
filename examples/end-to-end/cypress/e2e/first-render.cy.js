// The app's first render must be the real page, the same one the server sent.
//
// Elm draws its first view right away and every later view in an animation
// frame. Browsers do not run animation frames in a background tab, so whatever
// the first view shows is what a background tab shows (title included) until
// you switch to it.

import { holdAnimationFrames, recordTitles } from "../support/first-render.js";

function appHasStarted() {
  // The server sends this element with an empty data-url. The app fills it in.
  cy.get("[data-url]").should(($element) => {
    expect($element.attr("data-url")).to.include("localhost");
  });
}

context("first render", () => {
  it("shows the page and its title without waiting for an animation frame", () => {
    cy.visit("/", {
      onBeforeLoad(win) {
        recordTitles(win);
        holdAnimationFrames(win);
      },
    });
    appHasStarted();

    cy.contains("This is the index page.");
    cy.title().should("not.equal", "Page Data Error");
    cy.window().its("titlesSet").should("not.include", "Page Data Error");
  });

  it("still responds to events once animation frames run", () => {
    cy.visit("/counter", {
      onBeforeLoad(win) {
        recordTitles(win);
        holdAnimationFrames(win);
      },
    });
    appHasStarted();
    cy.window().then((win) => win.runHeldAnimationFrames());

    cy.contains("button", "+").click();
    cy.contains("Count: 1");
    cy.window().its("titlesSet").should("not.include", "Page Data Error");
  });

  it("shows the not found page without waiting for an animation frame", () => {
    cy.visit("/asdf", {
      failOnStatusCode: false,
      onBeforeLoad(win) {
        recordTitles(win);
        holdAnimationFrames(win);
      },
    });
    appHasStarted();

    cy.contains("No route found for /asdf");
    cy.window().its("titlesSet").should("not.include", "Page Data Error");
  });
});
