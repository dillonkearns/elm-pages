import { describe, it, expect } from "vitest";
import {
  parseLamderaVersion,
  lamderaVersionProblem,
} from "../src/lamdera-version.js";

describe("parseLamderaVersion", () => {
  it("reads the version from `lamdera --help`", () => {
    expect(
      parseLamderaVersion(
        "Hi, thank you for trying out Lamdera 1.5.0 on Elm 0.19.3. I hope you like it!\n\n---"
      )
    ).toEqual([1, 5, 0]);
  });

  it("gives null when there is no version to read", () => {
    expect(parseLamderaVersion("command not found")).toBeNull();
  });
});

describe("lamderaVersionProblem", () => {
  it("accepts the minimum version and newer ones", () => {
    expect(lamderaVersionProblem("Lamdera 1.5.0 on Elm 0.19.3")).toBeNull();
    expect(lamderaVersionProblem("Lamdera 1.5.1 on Elm 0.19.3")).toBeNull();
    expect(lamderaVersionProblem("Lamdera 1.10.0 on Elm 0.19.4")).toBeNull();
    expect(lamderaVersionProblem("Lamdera 2.0.0 on Elm 0.20.0")).toBeNull();
  });

  it("rejects older versions and says how to fix it", () => {
    const problem = lamderaVersionProblem("Lamdera 1.4.0 on Elm 0.19.1");

    expect(problem).toContain("Lamdera 1.5.0 or later");
    expect(problem).toContain("found Lamdera 1.4.0");
    expect(problem).toContain("npm install --save-dev lamdera@latest");
  });

  it("does not block when the version cannot be read", () => {
    // A future Lamdera might word its help text differently. Not being able
    // to read the version is no reason to stop someone from working.
    expect(lamderaVersionProblem("some new help text")).toBeNull();
  });
});
