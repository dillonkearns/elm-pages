globTest(1, ["content/index.md"]);
globTest(2, ["content/foo/index.md"]);
globTest(3, ["content/bar.md"]);
globTest(4, ["about", "posts"]);
globTest(5, [
  { first: "glob-test-cases/", second: "content1/", wildcard: "about.md" },
]);
globTest(6, [{ first: "data-file", second: "JSON" }]);
globTest(7, [{ year: 1977, month: 6, day: 10, slug: "apple-2-released" }]);
globTest(8, [["JSON", "YAML", "JSON", "JSON"]]);

function globTest(number, expected) {
  it(`glob test ${number}`, () => {
    cy.request("GET", `/glob-test/${number}`).then((res) => {
      console.log(number, res.body);
      expect(res.headers["content-type"]).to.eq("application/json");
      expect(res.status).to.eq(200);
      expect(res.body).to.deep.equal(expected);
    });
  });
}
