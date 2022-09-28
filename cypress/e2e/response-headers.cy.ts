context("dev server with base path", () => {
  it("navigating with a link successfully resolves data sources", () => {
    // cy.visit("/test/response-headers");
    // cy
    // cy.contains("Root page").click();
    // cy.contains("This is the index page.");
    cy.request("GET", "/test/response-headers/content.dat").then((res) => {
      expect(res.headers).to.include({
        "x-powered-by": "my-framework",
      });
      expect(res.status).to.eq(200);
    });
  });
});
