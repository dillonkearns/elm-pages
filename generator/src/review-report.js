/**
 * The message of the one error that the `Pages.Review.Canary` rule always
 * reports. Every elm-review run that elm-pages starts includes that rule, so a
 * report without this message means the run did not really happen.
 */
export const reviewCanaryMessage = "ELM_PAGES_REVIEW_CANARY";

/**
 * Check that an elm-review run really looked at the project.
 *
 * The build depends on elm-review to transform frozen views and remove dead
 * code. When elm-review gives back an empty report, or refuses the project, the
 * build would otherwise carry on and ship pages without those transforms.
 *
 * @param {string} elmReviewOutput - the output of `elm-review --report json`
 * @returns {string | null} a description of what went wrong, or null if all is well
 */
export function reviewReportProblem(elmReviewOutput) {
  let report;
  try {
    report = JSON.parse(elmReviewOutput);
  } catch (e) {
    return `elm-review did not give back a report. Its output was:\n\n${elmReviewOutput}`;
  }

  if (report.type !== "review-errors") {
    return [report.title, formattedText(report.message)]
      .filter(Boolean)
      .join("\n\n");
  }

  const errors = (report.errors || []).flatMap((file) => file.errors || []);

  const incorrectProject = errors.find(
    (error) => error.rule === "Incorrect project"
  );
  if (incorrectProject) {
    return [incorrectProject.message, ...(incorrectProject.details || [])].join(
      "\n\n"
    );
  }

  if (!errors.some((error) => error.message === reviewCanaryMessage)) {
    return `elm-review ran but did not report anything, not even the check that elm-pages builds into its rules. That means the rules did not really run.

A known cause is an old elm-review: run \`npx elm-review --version\` and update with \`npm install --save-dev elm-review@latest\`.`;
  }

  return null;
}

/**
 * elm-review's JSON errors carry their text as a list of strings and styled
 * `{ string }` pieces.
 *
 * @param {unknown} message
 * @returns {string}
 */
function formattedText(message) {
  if (typeof message === "string") {
    return message;
  }
  if (Array.isArray(message)) {
    return message
      .map((part) => (typeof part === "string" ? part : part.string || ""))
      .join("");
  }
  return "";
}
