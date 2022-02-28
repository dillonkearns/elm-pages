it(`glob tests`, () => {
  cy.request("GET", `/tests`).then((res) => {
    expect(res.headers["content-type"]).to.eq("text/plain");
    expect(res.status).to.eq(200);
    expect(res.body).to.match(/^Pass\n/)
  });
});