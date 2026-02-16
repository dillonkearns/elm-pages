context("frozen views regressions", () => {
  it("uses GET requests for GET form submissions", () => {
    cy.intercept("GET", "/get-form/content.dat?page=2").as("getFormGet");
    cy.intercept("POST", "/get-form/content.dat/**").as("getFormPost");

    cy.visit("/get-form");
    cy.contains("Page 2").click();

    cy.wait("@getFormGet");
    cy.get("@getFormPost.all").should("have.length", 0);
    cy.contains("Current page: 2");
    cy.location("search").should("eq", "?page=2");
  });

  it("keeps POST for empty-body submissions and handles absolute redirects", () => {
    cy.intercept("POST", "/absolute-redirect/content.dat/").as(
      "absoluteRedirectPost"
    );
    cy.intercept("GET", "/absolute-redirect/content.dat*").as(
      "absoluteRedirectGet"
    );

    cy.visit("/absolute-redirect");
    cy.contains("Submit Absolute Redirect").click();

    cy.wait("@absoluteRedirectPost");
    cy.get("@absoluteRedirectGet.all").should("have.length", 0);
    cy.location("pathname").should("eq", "/hello");
    cy.contains("Hello");
  });

  it("parses non-2xx content.dat payloads without forcing a full page reload", () => {
    cy.visit("/get-form");
    cy.window().then((win) => {
      win.__frozenViewsSpaMarker = "keep";
    });

    cy.intercept("GET", "/get-form/content.dat?page=2", (req) => {
      req.continue((res) => {
        res.statusCode = 404;
      });
    }).as("forced404ContentDat");

    cy.contains("Page 2").click();

    cy.wait("@forced404ContentDat");
    cy.contains("Current page: 2");
    cy.location("search").should("eq", "?page=2");
    cy.window().its("__frozenViewsSpaMarker").should("eq", "keep");
  });

  it("falls back to full page load for invalid content.dat payloads", () => {
    cy.visit("/get-form");
    cy.window().then((win) => {
      win.__frozenViewsReloadMarker = "set-before-submit";
    });

    cy.intercept("GET", "/get-form/content.dat?page=2", {
      statusCode: 500,
      headers: { "content-type": "application/octet-stream" },
      body: "not-a-valid-content-dat-payload",
    }).as("invalidContentDat");

    cy.contains("Page 2").click();

    cy.wait("@invalidContentDat");
    cy.location("search").should("eq", "?page=2");
    cy.contains("Current page: 2");
    cy.window().its("__frozenViewsReloadMarker").should("be.undefined");
  });
});
