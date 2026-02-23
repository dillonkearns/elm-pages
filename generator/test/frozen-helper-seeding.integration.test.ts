import {
  cpSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { sync as spawnSync } from "cross-spawn";
import { afterEach, describe, expect, it } from "vitest";

const testDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(testDir, "..", "..");
const fixtureRoot = join(testDir, "fixtures", "frozen-helper-seeding");
const fixtureProjectDir = join(fixtureRoot, "project");
const fixtureCasesDir = join(fixtureRoot, "cases");
const tempDirs: string[] = [];
const integrationTestTimeoutMs = 240_000;

const buildModes = [
  { name: "default", extraArgs: [] },
  { name: "strict", extraArgs: ["--strict"] },
] as const;

type BuildModeName = (typeof buildModes)[number]["name"];

function stripAnsi(input: string): string {
  return input.replace(/\x1B\[[0-9;]*m/g, "");
}

function listFixtureCaseIds(): string[] {
  const caseIds = readdirSync(fixtureCasesDir)
    .filter((entry) => statSync(join(fixtureCasesDir, entry)).isDirectory())
    .sort();

  if (caseIds.length === 0) {
    throw new Error(`No fixture cases found in ${fixtureCasesDir}`);
  }

  return caseIds;
}

function normalizeExpectedOutput(input: string): string {
  return input.replace(/\r\n/g, "\n").trimEnd();
}

function relevantBuildOutput(stdout: string, stderr: string): string {
  const combinedOutput = stripAnsi(`${stdout}\n${stderr}`);
  const lines = combinedOutput
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const keepLine = (line: string) =>
    line.includes("View.freeze warnings:") ||
    line.includes(
      "Build failed: unsupported helper usage for frozen ID seeding detected."
    ) ||
    line.includes("unsupported helper") ||
    line.includes(
      "Falling back to de-optimized frozen views for this build target (codemod fixes were skipped)."
    ) ||
    line.includes(
      "Refactor these call sites (or build without --strict to continue with de-optimized frozen views)."
    ) ||
    line.startsWith("- app/");

  return lines.filter(keepLine).join("\n");
}

function patchSourceDirectoriesForTempProject(tempProjectDir: string): void {
  const elmJsonPath = join(tempProjectDir, "elm.json");
  const elmJson = JSON.parse(readFileSync(elmJsonPath, "utf8"));

  elmJson["source-directories"] = [
    "src",
    "app",
    ".elm-pages",
    relative(tempProjectDir, join(repoRoot, "src")),
    relative(tempProjectDir, join(repoRoot, "plugins")),
    "elm-program-test-src",
  ];

  writeFileSync(elmJsonPath, JSON.stringify(elmJson, null, 4) + "\n");
}

function prepareProjectForCase(caseId: string): string {
  const tempProjectDir = mkdtempSync(
    join(testDir, `.tmp-frozen-helper-${caseId}-`)
  );
  tempDirs.push(tempProjectDir);
  cpSync(fixtureProjectDir, tempProjectDir, { recursive: true });
  cpSync(join(fixtureCasesDir, caseId, "scenario"), tempProjectDir, {
    recursive: true,
  });

  patchSourceDirectoriesForTempProject(tempProjectDir);
  return tempProjectDir;
}

function runElmPagesBuild(
  caseId: string,
  extraArgs: string[] = []
): { status: number; output: string } {
  const projectDir = prepareProjectForCase(caseId);
  const cliPath = join(repoRoot, "generator", "src", "cli.js");
  const result = spawnSync(
    "node",
    [cliPath, "build", "--keep-cache", ...extraArgs],
    {
      cwd: projectDir,
      env: { ...process.env, FORCE_COLOR: "0" },
      encoding: "utf8",
      timeout: 240_000,
    }
  );

  return {
    status: result.status ?? 1,
    output: relevantBuildOutput(result.stdout ?? "", result.stderr ?? ""),
  };
}

function readExpectedResult(
  caseId: string,
  modeName: BuildModeName
): { status: number; output: string } {
  const expectedDir = join(fixtureCasesDir, caseId, "expected");
  const statusPath = join(expectedDir, `${modeName}.status`);
  const outputPath = join(expectedDir, `${modeName}.output.txt`);

  const statusText = readFileSync(statusPath, "utf8").trim();
  const status = Number.parseInt(statusText, 10);

  if (Number.isNaN(status)) {
    throw new Error(
      `Invalid expected status in ${statusPath}: \"${statusText}\"`
    );
  }

  return {
    status,
    output: normalizeExpectedOutput(readFileSync(outputPath, "utf8")),
  };
}

describe.sequential("frozen helper seeding CLI behavior", () => {
  const caseIds = listFixtureCaseIds();

  afterEach(() => {
    for (const tempDir of tempDirs.splice(0)) {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  for (const caseId of caseIds) {
    for (const mode of buildModes) {
      it(
        `${caseId} (${mode.name})`,
        () => {
          const expected = readExpectedResult(caseId, mode.name);
          const result = runElmPagesBuild(caseId, mode.extraArgs);

          expect(result).toEqual(expected);
        },
        integrationTestTimeoutMs
      );
    }
  }
});
