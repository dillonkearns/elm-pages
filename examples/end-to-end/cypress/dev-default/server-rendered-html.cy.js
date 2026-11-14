// The HTML that the dev server sends, when it runs the way most people run it:
// plain `elm-pages dev`.
//
// The other dev server tests (cypress/e2e) run against `elm-pages dev --debug`.
// Some bugs only show up in one of the two modes.
// See https://github.com/dillonkearns/elm-pages/issues/622
//
// These tests use `cy.request` so they see the server's HTML, before the
// browser runs the app and draws the page again.

context("server-rendered HTML from the dev server (without --debug)", () => {
  it("includes lazy nodes that are inside keyed nodes", () => {
    cy.request("GET", "/lazy-in-keyed").then((res) => {
      expect(res.status).to.eq(200);
      expect(res.body).to.not.include("Error pre-rendering HTML");
      expect(res.body).to.include("Lazy node directly inside a keyed node");
      expect(res.body).to.include("Lazy node inside nested keyed nodes");
    });
  });
});
