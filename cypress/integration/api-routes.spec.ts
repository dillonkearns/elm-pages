it("JSON body", () => {
  cy.request("GET", "/api/greet", { first: "Dillon" }).then((res) => {
    expect(res.headers["content-type"]).to.eq("text/plain");
    expect(res.status).to.eq(200);
    expect(res.body).to.eq("Hello Dillon");
  });
});

it("JSON body with content-type metadata", () => {
  cy.request({
    method: "POST",
    url: "/api/greet",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ first: "Dillon" }),
  }).then((res) => {
    expect(res.headers["content-type"]).to.eq("text/plain");
    expect(res.status).to.eq(200);
    expect(res.body).to.eq("Hello Dillon");
  });
});

it("form post", () => {
  cy.request({
    method: "POST",
    url: "/api/greet",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ first: "Dillon" }).toString(),
  }).then((res) => {
    expect(res.headers["content-type"]).to.eq("text/plain");
    expect(res.status).to.eq(200);
    expect(res.body).to.eq("Hello Dillon");
  });
});

it("query param", () => {
  cy.request({
    method: "GET",
    url: "/api/greet?first=QueryParam",
  }).then((res) => {
    expect(res.headers["content-type"]).to.eq("text/plain");
    expect(res.status).to.eq(200);
    expect(res.body).to.eq("Hello QueryParam");
  });
});

it("expect query param when none present", () => {
  cy.request({
    method: "GET",
    url: "/api/greet",
    failOnStatusCode: false,
  }).then((res) => {
    expect(res.headers["content-type"]).to.eq("text/plain");
    expect(res.status).to.eq(400);
    expect(res.body).to.include(
      'Expected query param "first", but there were no query params.'
    );
  });
});

it("missing expected query param", () => {
  cy.request({
    method: "GET",
    url: "/api/greet?name=Jane",
    failOnStatusCode: false,
  }).then((res) => {
    expect(res.headers["content-type"]).to.eq("text/plain");
    expect(res.status).to.eq(400);
    expect(res.body).to.include('Missing query param "first"');
  });
});

it("multi-part form post", () => {
  const formData = new FormData();
  formData.set("first", "Multipart");
  cy.request({
    method: "POST",
    url: "/api/greet",
    body: formData,
  }).then((res) => {
    expect(res.headers["content-type"]).to.eq("text/plain");
    expect(res.status).to.eq(200);
    expect(Cypress.Blob.arrayBufferToBinaryString(res.body)).to.eq(
      "Hello Multipart"
    );
  });
});
