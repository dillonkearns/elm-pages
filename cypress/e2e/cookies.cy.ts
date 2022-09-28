context("cookies", () => {
  it("shows no preference message when no cookie", () => {
    cy.clearCookies();
    cy.visit("/cookie-test");
    cy.contains("No dark mode preference set");
  });

  it("saves session cookie", () => {
    cy.setCookie("dark-mode", "true");
    cy.visit("/cookie-test");
    cy.contains("Dark mode: true");
  });
});
