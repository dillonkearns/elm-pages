/// <reference types="Cypress" />

context("fetchers", () => {
  it("add items to list", () => {
    cy.visit("/fetcher");
    cy.get("#delete-all button").click();

    addItem("1");
    addItem("2");
    addItem("3");

    expectList("1", "2", "3");
  });
});

function addItem(itemName) {
  cy.get("input[name=name]").clear().type(itemName);
  cy.contains("Submit").click();
}

function expectList(...list) {
  cy.get("ul>li")
    .should("have.length", 3)
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
