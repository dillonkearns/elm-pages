import { describe, it, expect } from "vitest";
import { reviewReportProblem, reviewCanaryMessage } from "../src/review-report.js";
import {
  parseElmReviewVersion,
  elmReviewVersionProblem,
} from "../src/elm-review-version.js";

const canary = {
  path: null,
  errors: [{ rule: "Pages.Review.Canary", message: reviewCanaryMessage }],
};

/** @param {object} report */
const output = (report) => JSON.stringify(report);

describe("reviewReportProblem", () => {
  it("accepts a report that has the canary", () => {
    expect(
      reviewReportProblem(output({ type: "review-errors", errors: [canary] }))
    ).toBeNull();
  });

  it("rejects a report with no results at all", () => {
    // What elm-review 2.13.2 gives back when Lamdera compiles its rules:
    // a normal looking report that silently found nothing.
    const problem = reviewReportProblem(
      output({ type: "review-errors", errors: [], extracts: {} })
    );

    expect(problem).toContain("did not report anything");
    expect(problem).toContain("elm-review");
  });

  it("rejects a project that elm-review refuses to look at", () => {
    const problem = reviewReportProblem(
      output({
        type: "review-errors",
        errors: [
          {
            path: null,
            errors: [
              {
                rule: "Incorrect project",
                message: "Found several modules named `TuiTests`",
                details: ["I found several modules with the name `TuiTests`."],
              },
            ],
          },
        ],
      })
    );

    expect(problem).toContain("Found several modules named `TuiTests`");
    expect(problem).toContain("I found several modules with the name");
  });

  it("rejects a tool error", () => {
    const problem = reviewReportProblem(
      output({ type: "error", title: "CONFIGURATION ERROR", message: ["Oh no"] })
    );

    expect(problem).toContain("CONFIGURATION ERROR");
    expect(problem).toContain("Oh no");
  });

  it("rejects output that is not a report", () => {
    expect(reviewReportProblem("Segmentation fault")).toContain(
      "Segmentation fault"
    );
  });
});

describe("elm-review version", () => {
  it("reads the version from `elm-review --version`", () => {
    expect(parseElmReviewVersion("2.13.5\n")).toEqual([2, 13, 5]);
    expect(parseElmReviewVersion("nope")).toBeNull();
  });

  it("accepts versions that work with Lamdera", () => {
    expect(elmReviewVersionProblem("2.13.3")).toBeNull();
    expect(elmReviewVersionProblem("2.13.5")).toBeNull();
    expect(elmReviewVersionProblem("2.14.0")).toBeNull();
    expect(elmReviewVersionProblem("3.0.0")).toBeNull();
  });

  it("rejects versions that silently find nothing with Lamdera", () => {
    const problem = elmReviewVersionProblem("2.13.2");

    expect(problem).toContain("elm-review 2.13.3 or later");
    expect(problem).toContain("found elm-review 2.13.2");
    expect(problem).toContain("npm install --save-dev elm-review@latest");
    expect(elmReviewVersionProblem("2.12.0")).not.toBeNull();
  });
});
