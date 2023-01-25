import * as assert from "assert";

import { sortTemplates } from "../src/generate-template-module-connector.js";
describe("sort", function () {
  it("purely static comes before dynamic routes", function () {
    assert.deepStrictEqual(
      sortTemplates([
        ["Post", "Create"],
        ["Post", "Slug_"],
      ]),

      [
        ["Post", "Create"],
        ["Post", "Slug_"],
      ]
    );
  });
  it("more static segments breaks ties for same number of dynamic segments", function () {
    assert.deepStrictEqual(
      sortTemplates([
        ["Repo_", "User_"],
        ["Project", "New"],
      ]),

      [
        ["Project", "New"],
        ["Repo_", "User_"],
      ]
    );
  });
  it("splats come last", function () {
    assert.deepStrictEqual(
      sortTemplates([
        ["SPLAT_"],
        ["Repo", "Username_", "Project_"],
        ["Project", "New"],
      ]),

      [["Project", "New"], ["Repo", "Username_", "Project_"], ["SPLAT_"]]
    );
  });
  it("purely static comes before route with optional param", function () {
    assert.deepStrictEqual(
      sortTemplates([["Docs"], ["Docs", "Section__"]]),

      [["Docs"], ["Docs", "Section__"]]
    );
  });
});
