it("greets", () => {
  cy.request("GET", "/api/greet", { first: "Dillon" }).then((res) => {
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
