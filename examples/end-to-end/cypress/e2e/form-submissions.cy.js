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
  it("redirect updates URL before any further navigation", () => {
    // Verify the URL is correct so that clicking a link from the
    // redirected page navigates relative to /greet, not /login
    cy.visit("/login");
    cy.get("input[name=name]").clear().type("Alice");
    cy.get("button").click();
    cy.url().should("include", "/greet");
    cy.contains("Hello Alice!");
    // Navigate away and back to confirm URL state is consistent
    cy.visit("/");
    cy.visit("/greet?name=Bob");
    cy.url().should("include", "/greet");
    cy.contains("Hello Bob!");
  });
  it("redirect clears form state", () => {
    // After redirect, going back to login should show a clean form
    cy.visit("/login");
    cy.get("input[name=name]").clear().type("Dave");
    cy.get("button").click();
    cy.url().should("include", "/greet");
    cy.contains("Hello Dave!");
    // Navigate back to login — form state should be cleared
    cy.visit("/login");
    cy.contains("You aren't logged in yet.").should("not.exist");
    // Should show logged-in state from session, not stale form data
    cy.contains("Hello Dave!");
  });
  it("form validation errors stay on the same page", () => {
    cy.visit("/login");
    cy.get("input[name=name]").clear().type("error");
    cy.get("button").click();
    // Should stay on /login with validation error, not redirect
    cy.url().should("include", "/login");
    cy.contains("Invalid username");
    // URL should still be /login
    cy.url().should("not.include", "/greet");
  });
});
