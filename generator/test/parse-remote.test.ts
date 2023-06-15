import * as assert from "assert";
import { describe, it } from "vitest";
import { parse } from "../src/parse-remote.js";

describe("parse GitHub URL", function () {
  it("repo URL", function () {
    assert.deepEqual(
      parse("https://github.com/dillonkearns/elm-pages-starter"),
      {
        remote: "https://github.com/dillonkearns/elm-pages-starter.git",
        filePath: null,
        branch: null,
        owner: "dillonkearns",
        repo: "elm-pages-starter",
      }
    );
  });
  it("repo URL with file", function () {
    assert.deepEqual(
      parse(
        "https://github.com/dillonkearns/elm-pages-starter/blob/main/script/src/Stars.elm"
      ),
      {
        remote: "https://github.com/dillonkearns/elm-pages-starter.git",
        filePath: "script/src/Stars.elm",
        branch: "main",
        owner: "dillonkearns",
        repo: "elm-pages-starter",
      }
    );
  });
  it("raw github URL", function () {
    assert.deepEqual(
      parse(
        "https://raw.githubusercontent.com/dillonkearns/elm-pages-starter/master/script/src/Stars.elm"
      ),
      {
        remote: "https://github.com/dillonkearns/elm-pages-starter.git",
        filePath: "script/src/Stars.elm",
        branch: "master",
        owner: "dillonkearns",
        repo: "elm-pages-starter",
      }
    );
  });
  it("raw gist URL with owner", function () {
    assert.deepEqual(
      parse(
        "https://gist.github.com/dillonkearns/4f050018784b25246729a82fc9907543"
      ),
      {
        remote: "https://gist.github.com/4f050018784b25246729a82fc9907543.git",
        filePath: "Main.elm",
        branch: null,
        owner: "dillonkearns",
        repo: "4f050018784b25246729a82fc9907543",
      }
    );
  });
  it("raw gist URL without owner", function () {
    assert.deepEqual(
      parse("https://gist.github.com/4f050018784b25246729a82fc9907543"),
      {
        remote: "https://gist.github.com/4f050018784b25246729a82fc9907543.git",
        filePath: "Main.elm",
        branch: null,
        owner: "gist",
        repo: "4f050018784b25246729a82fc9907543",
      }
    );
  });
  it("raw gist asset URL with file path", function () {
    assert.deepEqual(
      parse(
        "https://gist.githubusercontent.com/dillonkearns/4f050018784b25246729a82fc9907543/raw/84f671b5547b98f5496e95c93fb1dee33c6d213b/Main.elm"
      ),
      {
        remote: "https://gist.github.com/4f050018784b25246729a82fc9907543.git",
        filePath: "Main.elm",
        branch: null,
        owner: "dillonkearns",
        repo: "4f050018784b25246729a82fc9907543",
      }
    );
  });
  it("github:repo:path", function () {
    assert.deepEqual(
      parse("github:dillonkearns/elm-pages-starter:script/src/Stars.elm"),
      {
        remote: "https://github.com/dillonkearns/elm-pages-starter.git",
        filePath: "script/src/Stars.elm",
        branch: null,
        owner: "dillonkearns",
        repo: "elm-pages-starter",
      }
    );
  });
});
