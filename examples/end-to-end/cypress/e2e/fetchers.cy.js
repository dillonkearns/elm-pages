/// <reference types="Cypress" />

context("fetchers", () => {
  it("add items to list", () => {
    cy.visit("/fetcher");
    cy.contains("Ready");
    cy.get("#delete-all button").click();

    cy.contains("Deleting...");
    cy.contains("Ready");

    addItem("500");
    cy.wait(100);
    addItem("5");
    cy.wait(100);
    addItem("501");
    expectList("5", "500", "501");
  });
});

function addItem(itemName) {
  cy.get("input[name=name]").clear({ force: true });
  cy.get("input[name=name]").type(itemName, { force: true });
  cy.contains("Submit").click();
}

function expectList(...list) {
  cy.get("ul#items>li.loading").should("have.length", 0);
  cy.get("ul#items>li")
    .should("have.length", list.length)
    .then(($els) => {
      // source: https://glebbahmutov.com/cypress-examples/7.1.0/recipes/get-text-list.html#getting-text-from-list-of-elements
      // we get a list of jQuery elements
      // let's convert the jQuery object into a plain array
      return (
        Cypress.$.makeArray($els)
          // and extract inner text from each
          .map((el) => el.innerText)
      );
    })
    .should("deep.equal", list);
}
