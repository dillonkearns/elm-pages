context("dev server with base path", () => {
  it("fills name field with 'Jim' when clicking a new button", () => {
    cy.visit("/form");
    cy.get("input[name=first]").should("have.value", "Jane");
    cy.get("button#fill-jim").click();
    cy.get("input[name=first]").should("have.value", "Jim");
  });
  it("submits a form to receive ActionData", () => {
    cy.visit("/form");
    cy.get("input[name=first]").clear().type("John");
    cy.get("input[name=last]").clear().type("Asdf");
    cy.get("button#update").click();
    cy.contains("Successfully received user John Asdf");
  });
  it.skip("logs in and out", () => {
    cy.visit("/login");
    cy.get("input[name=name]").clear().type("John");
    cy.get("button").click();
    cy.contains("Hello John!");
    cy.contains("Logout").click();
    cy.contains("You have been successfully logged out.");
  });
  it("logs in with errors then re-submits form successfully", () => {
    cy.visit("/login");
    cy.get("input[name=name]").clear().type("error");
    cy.get("button").click();
    cy.contains("Invalid username");
    cy.get("input[name=name]").clear().type("John");
    cy.get("button").click();
    cy.contains("Hello John");
  });
});
