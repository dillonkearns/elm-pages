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
    it("gives error when route doesn't match", () => {
        cy.clearCookies();
        cy.visit("http://localhost:1234/dark-mode");
        cy.contains("Current mode: Light Mode");
        cy.get("button").click();
        cy.contains("Current mode: Dark Mode");
    });
});
export {};
