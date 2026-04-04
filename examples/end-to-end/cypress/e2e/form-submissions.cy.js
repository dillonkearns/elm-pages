context("dev server with base path", () => {
  it("submits a form to receive ActionData", () => {
    cy.visit("/form");
    cy.get("input[name=first]").clear().type("John");
    cy.get("input[name=last]").clear().type("Asdf");
    cy.get("button").click();
    cy.contains("Successfully received user John Asdf");
  });
  it("logs in and redirects to greet page", () => {
    cy.visit("/login");
    cy.contains("You aren't logged in yet.");
    cy.get("input[name=name]").clear().type("John");
    cy.get("button").click();
    // After form submit, should redirect to /greet with session
    cy.url().should("include", "/greet");
    cy.contains("Hello John!");
  });
  it.skip("logs in and out", () => {
    cy.visit("/login");
    cy.get("input[name=name]").clear().type("John");
    cy.get("button").click();
    cy.contains("Hello John!");
    cy.contains("Logout").click();
    cy.contains("You have been successfully logged out.");
  });
  it.skip("logs in with errors then re-submits form successfully", () => {
    cy.visit("/login");
    cy.get("input[name=name]").clear().type("error");
    cy.get("button").click();
    cy.contains("Invalid username");
    cy.get("input[name=name]").clear().type("John");
    cy.get("button").click();
    cy.contains("Hello John");
  });
});
