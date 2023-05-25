context("dev server 404 page", () => {
  it("gives error when route doesn't match", () => {
    cy.visit("http://localhost:1234/asdf", { failOnStatusCode: false });
    cy.contains("No route found for /asdf");
  });

  it("gives error when route matches but page isn't pre-rendered", () => {
    cy.visit("http://localhost:1234/blog/non-existent-page", {
      failOnStatusCode: false,
    });
    cy.contains(
      `/blog/non-existent-page successfully matched the route /blog/:slug from the Route Module src/Blog/Slug_.elm`
    );
    cy.contains(
      `But this Page module has no pre-rendered routes! If you want to pre-render this page, add these RouteParams to the module's routes`
    );
    cy.contains(`{ slug = "non-existent-page" }`);
  });
});
