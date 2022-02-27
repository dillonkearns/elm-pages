globTest(1, ["content/index.md"]);
globTest(2, ["content/foo/index.md"]);
globTest(3, ["content/bar.md"]);

function globTest(number, expected) {
  it(`glob test ${number}`, () => {
    cy.request("GET", `/glob-test/${number}`).then((res) => {
      expect(res.headers["content-type"]).to.eq("text/plain");
      expect(res.status).to.eq(200);
      expect(res.body.split(",")).to.deep.equal(expected);
    });
  });
}
