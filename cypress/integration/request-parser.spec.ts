it("JSON body", () => {
  const body = { first: "Dillon" };
  cy.setCookie("theme", "dark");
  cy.request("GET", "/api/request-test?param1=value1&param2=value2", body).then(
    (res) => {
      expect(res.headers["content-type"]).to.eq("application/json");
      expect(res.status).to.eq(200);
      expect(res.body).to.deep.eq({
        method: "GET",
        rawBody: JSON.stringify(body),
        cookies: { theme: "dark" },
        queryParams: { param1: ["value1"], param2: ["value2"] },
      });
    }
  );
});

it("empty body", () => {
  cy.setCookie("theme", "dark");
  cy.request("GET", "/api/request-test").then((res) => {
    expect(res.headers["content-type"]).to.eq("application/json");
    expect(res.status).to.eq(200);
    expect(res.body.rawBody).to.be.null;
  });
});
