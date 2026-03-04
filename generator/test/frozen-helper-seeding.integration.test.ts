import {
  cpSync,
  existsSync,
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
import { extractFrozenViews } from "../src/extract-frozen-views.js";

const testDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(testDir, "..", "..");
const fixtureRoot = join(testDir, "fixtures", "frozen-helper-seeding");
const fixtureProjectDir = join(fixtureRoot, "project");
const fixtureCasesDir = join(fixtureRoot, "cases");
const tempDirs: string[] = [];
const integrationTestTimeoutMs = 1_200_000;

const buildModes = [
  { name: "default", extraArgs: [] },
  { name: "strict", extraArgs: ["--strict"] },
] as const;

type BuildModeName = (typeof buildModes)[number]["name"];
type RawBuildResult = {
  status: number;
  stdout: string;
  stderr: string;
  projectDir: string;
};

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
  const sourceDirectories = elmJson["source-directories"];

  if (!Array.isArray(sourceDirectories)) {
    throw new Error(`Invalid source-directories in ${elmJsonPath}`);
  }

  const rewrittenSourceDirectories = sourceDirectories.map((sourceDirectory) => {
    if (sourceDirectory === "../../src") {
      return relative(tempProjectDir, join(repoRoot, "src"));
    }

    if (sourceDirectory === "../../plugins") {
      return relative(tempProjectDir, join(repoRoot, "plugins"));
    }

    return sourceDirectory;
  });

  elmJson["source-directories"] = [...new Set(rewrittenSourceDirectories)];

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
  const rawResult = runElmPagesBuildRaw(caseId, extraArgs);
  return {
    status: rawResult.status,
    output: relevantBuildOutput(rawResult.stdout, rawResult.stderr),
  };
}

function runElmPagesBuildRaw(
  caseId: string,
  extraArgs: string[] = []
): RawBuildResult {
  const cliPath = join(repoRoot, "generator", "src", "cli.js");

  for (let attempt = 0; attempt < 2; attempt++) {
    const projectDir = prepareProjectForCase(caseId);
    const result = spawnSync(
      "node",
      [cliPath, "build", "--keep-cache", ...extraArgs],
      {
        cwd: projectDir,
        env: { ...process.env, FORCE_COLOR: "0" },
        encoding: "utf8",
        timeout: 1_200_000,
      }
    );

    const rawResult: RawBuildResult = {
      status: result.status ?? 1,
      stdout: result.stdout ?? "",
      stderr: result.stderr ?? "",
      projectDir,
    };

    const hasOutput =
      rawResult.stdout.trim().length > 0 || rawResult.stderr.trim().length > 0;
    if (rawResult.status === 0 || hasOutput || attempt === 1) {
      return rawResult;
    }
  }

  throw new Error(`Unreachable: failed to run build for fixture ${caseId}`);
}

function parseFrozenViewsPrefixFromBytes(
  bytes: Buffer
): { regions: Record<string, string>; remainingByteLength: number } {
  if (bytes.length < 4) {
    throw new Error("Expected at least 4 bytes for frozen views length prefix.");
  }

  const frozenViewsLength = bytes.readUInt32BE(0);
  const frozenViewsEnd = 4 + frozenViewsLength;
  const frozenViewsJson = bytes.slice(4, frozenViewsEnd).toString("utf8");

  return {
    regions: JSON.parse(frozenViewsJson),
    remainingByteLength: Math.max(0, bytes.length - frozenViewsEnd),
  };
}

function extractBytesDataBase64(indexHtml: string): string {
  const match = indexHtml.match(
    /<script id="__ELM_PAGES_BYTES_DATA__" type="application\/octet-stream">([^<]+)<\/script>/
  );

  if (!match || !match[1]) {
    throw new Error("Could not find __ELM_PAGES_BYTES_DATA__ script tag.");
  }

  return match[1];
}

function findModuleFileInWorkspace(
  workspaceDir: string,
  moduleRelativePath: string
): string {
  const elmJsonPath = join(workspaceDir, "elm.json");
  const elmJson = JSON.parse(readFileSync(elmJsonPath, "utf8"));
  const sourceDirectories = elmJson["source-directories"];

  if (!Array.isArray(sourceDirectories)) {
    throw new Error(`Invalid source-directories in ${elmJsonPath}`);
  }

  for (const sourceDirectory of sourceDirectories) {
    const candidatePath = join(workspaceDir, sourceDirectory, moduleRelativePath);
    if (existsSync(candidatePath)) {
      return candidatePath;
    }
  }

  throw new Error(
    `Could not find ${moduleRelativePath} in workspace ${workspaceDir}`
  );
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

function assertSupportedHelperSeedingAgreement(caseId: string): void {
  const result = runElmPagesBuildRaw(caseId);
  expect(result.status).toBe(0);

  const indexHtmlPath = join(result.projectDir, "dist", "index.html");
  const contentDatPath = join(result.projectDir, "dist", "content.dat");
  const indexHtml = readFileSync(indexHtmlPath, "utf8");
  const contentDatBytes = readFileSync(contentDatPath);

  const extractedFromHtml = extractFrozenViews(indexHtml);
  const contentDatDecoded = parseFrozenViewsPrefixFromBytes(contentDatBytes);

  expect(Object.keys(contentDatDecoded.regions).sort()).toEqual(["0:0", "1:0"]);
  expect(contentDatDecoded.regions).toEqual(extractedFromHtml);
  expect(contentDatDecoded.regions["0:0"]).toContain("User: Alice");
  expect(contentDatDecoded.regions["1:0"]).toContain("User: Bob");
  expect(contentDatDecoded.remainingByteLength).toBeGreaterThan(0);

  const bytesDataBase64 = extractBytesDataBase64(indexHtml);
  const bytesDataDecoded = parseFrozenViewsPrefixFromBytes(
    Buffer.from(bytesDataBase64, "base64")
  );
  expect(bytesDataDecoded.regions).toEqual({});
  expect(bytesDataDecoded.remainingByteLength).toBeGreaterThan(0);

  const clientWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "client");
  const serverWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "server");
  const clientHelperPath = findModuleFileInWorkspace(
    clientWorkspace,
    join("Ui", "FrozenHelper.elm")
  );
  const serverHelperPath = findModuleFileInWorkspace(
    serverWorkspace,
    join("Ui", "FrozenHelper.elm")
  );
  const clientHelper = readFileSync(clientHelperPath, "utf8");
  const serverHelper = readFileSync(serverHelperPath, "utf8");

  expect(clientHelper).toContain(
    "summaryCard : String -> { name : String } -> Html msg"
  );
  expect(serverHelper).toContain(
    "summaryCard : String -> { name : String } -> Html msg"
  );
  expect(clientHelper).toContain("++ \":0\")");
  expect(serverHelper).toContain("++ \":0\")");

  const clientRoute = readFileSync(
    join(clientWorkspace, "app", "Route", "Index.elm"),
    "utf8"
  );
  const serverRoute = readFileSync(
    join(serverWorkspace, "app", "Route", "Index.elm"),
    "utf8"
  );
  const callSeedPattern = /summaryCard \"([^\"]+)\"/g;
  const clientSeeds = [...clientRoute.matchAll(callSeedPattern)].map(
    (match) => match[1]
  );
  const serverSeeds = [...serverRoute.matchAll(callSeedPattern)].map(
    (match) => match[1]
  );

  expect(clientSeeds).toEqual(["0", "1"]);
  expect(serverSeeds).toEqual(clientSeeds);
}

function assertMixedSupportedAndUnsupportedBehavior(caseId: string): void {
  const result = runElmPagesBuildRaw(caseId);
  expect(result.status).toBe(0);

  const indexHtmlPath = join(result.projectDir, "dist", "index.html");
  const contentDatPath = join(result.projectDir, "dist", "content.dat");
  const indexHtml = readFileSync(indexHtmlPath, "utf8");
  const contentDatBytes = readFileSync(contentDatPath);
  const extractedFromHtml = extractFrozenViews(indexHtml);
  const contentDatDecoded = parseFrozenViewsPrefixFromBytes(contentDatBytes);

  expect(contentDatDecoded.regions).toEqual(extractedFromHtml);
  expect(Object.keys(contentDatDecoded.regions).length).toBeGreaterThan(0);
  expect(
    Object.values(contentDatDecoded.regions).some((region) =>
      region.includes("Direct: Hello")
    )
  ).toBe(true);

  const clientRoute = readFileSync(
    join(result.projectDir, "elm-stuff", "elm-pages", "client", "app", "Route", "Index.elm"),
    "utf8"
  );
  expect(clientRoute).toContain("__ELM_PAGES_STATIC__");
}

function assertSupportedHelperAdoptionWithUnrelatedUnsupported(
  caseId: string
): void {
  const result = runElmPagesBuildRaw(caseId);
  expect(result.status).toBe(0);

  const indexHtmlPath = join(result.projectDir, "dist", "index.html");
  const contentDatPath = join(result.projectDir, "dist", "content.dat");
  const indexHtml = readFileSync(indexHtmlPath, "utf8");
  const contentDatBytes = readFileSync(contentDatPath);
  const extractedFromHtml = extractFrozenViews(indexHtml);
  const contentDatDecoded = parseFrozenViewsPrefixFromBytes(contentDatBytes);

  expect(contentDatDecoded.regions).toEqual(extractedFromHtml);
  expect(Object.keys(contentDatDecoded.regions).sort()).toEqual(["0:0"]);
  expect(contentDatDecoded.regions["0:0"]).toContain("Supported: Alice");

  const clientWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "client");
  const serverWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "server");
  const clientHelperPath = findModuleFileInWorkspace(
    clientWorkspace,
    join("Ui", "SupportedHelper.elm")
  );
  const serverHelperPath = findModuleFileInWorkspace(
    serverWorkspace,
    join("Ui", "SupportedHelper.elm")
  );
  const clientHelper = readFileSync(clientHelperPath, "utf8");
  const serverHelper = readFileSync(serverHelperPath, "utf8");

  expect(clientHelper).toContain(
    "summaryCard : String -> { name : String } -> Html msg"
  );
  expect(serverHelper).toContain(
    "summaryCard : String -> { name : String } -> Html msg"
  );
}

function assertDirectRepeatedFreezeDeOptimized(caseId: string): void {
  const result = runElmPagesBuildRaw(caseId);
  expect(result.status).toBe(0);

  const clientWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "client");
  const clientRoutePath = findModuleFileInWorkspace(
    clientWorkspace,
    join("Route", "Index.elm")
  );
  const clientRoute = readFileSync(clientRoutePath, "utf8");

  // Repeated direct View.freeze in lambda contexts must not be rewritten to static IDs.
  expect(clientRoute).toContain("View.freeze");
  expect(clientRoute).not.toContain("__ELM_PAGES_STATIC__");
}

function assertRouteLocalHelperSeedingAgreement(caseId: string): void {
  const result = runElmPagesBuildRaw(caseId);
  expect(result.status).toBe(0);

  const indexHtmlPath = join(result.projectDir, "dist", "index.html");
  const contentDatPath = join(result.projectDir, "dist", "content.dat");
  const indexHtml = readFileSync(indexHtmlPath, "utf8");
  const contentDatBytes = readFileSync(contentDatPath);

  const extractedFromHtml = extractFrozenViews(indexHtml);
  const contentDatDecoded = parseFrozenViewsPrefixFromBytes(contentDatBytes);

  expect(Object.keys(contentDatDecoded.regions).sort()).toEqual(["0:0", "1:0"]);
  expect(contentDatDecoded.regions).toEqual(extractedFromHtml);
  expect(contentDatDecoded.regions["0:0"]).toContain("User: Alice");
  expect(contentDatDecoded.regions["1:0"]).toContain("User: Bob");

  const clientWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "client");
  const serverWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "server");
  const clientRoutePath = findModuleFileInWorkspace(
    clientWorkspace,
    join("Route", "Index.elm")
  );
  const serverRoutePath = findModuleFileInWorkspace(
    serverWorkspace,
    join("Route", "Index.elm")
  );
  const clientRoute = readFileSync(clientRoutePath, "utf8");
  const serverRoute = readFileSync(serverRoutePath, "utf8");

  expect(clientRoute).toContain('card "0" app.data.alice');
  expect(clientRoute).toContain('card "1" app.data.bob');
  expect(serverRoute).toContain('card "0" app.data.alice');
  expect(serverRoute).toContain('card "1" app.data.bob');
  expect(clientRoute).toContain("card elmPagesFid_route_index_card");
  expect(serverRoute).toContain("card elmPagesFid_route_index_card");
  expect(clientRoute).toContain(
    '__ELM_PAGES_STATIC__" ++ elmPagesFid_route_index_card ++ ":0"'
  );
  expect(serverRoute).toContain(
    'data-static" (elmPagesFid_route_index_card ++ ":0")'
  );
}

function assertSharedLocalHelperSeedingAgreement(caseId: string): void {
  const result = runElmPagesBuildRaw(caseId);
  expect(result.status).toBe(0);

  const indexHtmlPath = join(result.projectDir, "dist", "index.html");
  const contentDatPath = join(result.projectDir, "dist", "content.dat");
  const indexHtml = readFileSync(indexHtmlPath, "utf8");
  const contentDatBytes = readFileSync(contentDatPath);

  const extractedFromHtml = extractFrozenViews(indexHtml);
  const contentDatDecoded = parseFrozenViewsPrefixFromBytes(contentDatBytes);

  expect(Object.keys(contentDatDecoded.regions).sort()).toEqual([
    "shared:0:0",
    "shared:1:0",
  ]);
  expect(contentDatDecoded.regions).toEqual(extractedFromHtml);
  expect(contentDatDecoded.regions["shared:0:0"]).toContain("Shared user: Alice");
  expect(contentDatDecoded.regions["shared:1:0"]).toContain("Shared user: Bob");

  const clientWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "client");
  const serverWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "server");
  const clientShared = readFileSync(join(clientWorkspace, "app", "Shared.elm"), "utf8");
  const serverShared = readFileSync(join(serverWorkspace, "app", "Shared.elm"), "utf8");

  expect(clientShared).toContain("sharedCard : String -> { name : String } -> Html msg");
  expect(serverShared).toContain("sharedCard : String -> { name : String } -> Html msg");
  expect(clientShared).toContain('sharedCard "shared:0" { name = "Alice" }');
  expect(clientShared).toContain('sharedCard "shared:1" { name = "Bob" }');
  expect(serverShared).toContain('sharedCard "shared:0" { name = "Alice" }');
  expect(serverShared).toContain('sharedCard "shared:1" { name = "Bob" }');
  expect(clientShared).toContain("sharedCard elmPagesFid_shared_sharedcard user");
  expect(serverShared).toContain("sharedCard elmPagesFid_shared_sharedcard user");
  expect(clientShared).toContain(
    '__ELM_PAGES_STATIC__" ++ elmPagesFid_shared_sharedcard ++ ":0"'
  );
  expect(serverShared).toContain(
    'data-static" (elmPagesFid_shared_sharedcard ++ ":0")'
  );
}

function assertRouteLocalMixedCallsiteFallback(caseId: string): void {
  const result = runElmPagesBuildRaw(caseId);
  expect(result.status).toBe(0);

  const output = relevantBuildOutput(result.stdout, result.stderr);
  expect(output).toContain("unsupported helper usage detected");
  expect(output).toContain(
    "Frozen view codemod: unsupported helper function value or partial application"
  );

  const indexHtmlPath = join(result.projectDir, "dist", "index.html");
  const contentDatPath = join(result.projectDir, "dist", "content.dat");
  const indexHtml = readFileSync(indexHtmlPath, "utf8");
  const contentDatBytes = readFileSync(contentDatPath);

  const extractedFromHtml = extractFrozenViews(indexHtml);
  const contentDatDecoded = parseFrozenViewsPrefixFromBytes(contentDatBytes);

  // Current fallback strategy excludes the route file when unsupported helper call forms exist.
  expect(contentDatDecoded.regions).toEqual({});
  expect(extractedFromHtml).toEqual({});

  const clientWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "client");
  const serverWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "server");
  const clientRoutePath = findModuleFileInWorkspace(
    clientWorkspace,
    join("Route", "Index.elm")
  );
  const serverRoutePath = findModuleFileInWorkspace(
    serverWorkspace,
    join("Route", "Index.elm")
  );
  const clientRoute = readFileSync(clientRoutePath, "utf8");
  const serverRoute = readFileSync(serverRoutePath, "utf8");

  expect(clientRoute).toContain("List.map card");
  expect(clientRoute).toContain("card app.data.alice");
  expect(clientRoute).not.toContain("__ELM_PAGES_STATIC__");
  expect(serverRoute).not.toContain("data-static");
}

function assertSharedAndRouteUnsupportedImporterFallback(caseId: string): void {
  const result = runElmPagesBuildRaw(caseId);
  expect(result.status).toBe(0);

  const output = relevantBuildOutput(result.stdout, result.stderr);
  expect(output).toContain("unsupported helper usage detected");
  expect(output).toContain(
    "Frozen view codemod: unsupported helper function value or partial application"
  );

  const indexHtmlPath = join(result.projectDir, "dist", "index.html");
  const contentDatPath = join(result.projectDir, "dist", "content.dat");
  const indexHtml = readFileSync(indexHtmlPath, "utf8");
  const contentDatBytes = readFileSync(contentDatPath);

  const extractedFromHtml = extractFrozenViews(indexHtml);
  const contentDatDecoded = parseFrozenViewsPrefixFromBytes(contentDatBytes);

  // Cross-module fallback should not produce seeded frozen IDs in this matrix case.
  expect(extractedFromHtml).toEqual({});
  expect(contentDatDecoded.regions).toEqual({});

  const clientWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "client");
  const serverWorkspace = join(result.projectDir, "elm-stuff", "elm-pages", "server");
  const clientShared = readFileSync(join(clientWorkspace, "app", "Shared.elm"), "utf8");
  const serverShared = readFileSync(join(serverWorkspace, "app", "Shared.elm"), "utf8");
  const clientRoute = readFileSync(join(clientWorkspace, "app", "Route", "Index.elm"), "utf8");
  const serverRoute = readFileSync(join(serverWorkspace, "app", "Route", "Index.elm"), "utf8");
  const clientHelper = readFileSync(
    join(clientWorkspace, "app", "FrozenHelper.elm"),
    "utf8"
  );

  expect(clientShared).toContain('FrozenHelper.summaryCard { name = "Shared A" }');
  expect(clientShared).not.toContain('FrozenHelper.summaryCard "shared:');
  expect(clientRoute).toContain("List.map FrozenHelper.summaryCard app.data.users");
  expect(clientRoute).toContain('FrozenHelper.summaryCard { name = "Route static" }');
  expect(clientRoute).not.toContain('FrozenHelper.summaryCard "');
  expect(serverRoute).not.toContain('data-static"');
  expect(serverShared).not.toContain('data-static"');
  expect(clientHelper).toContain("summaryCard user =");
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

  it(
    "supported-helper-src-module emits matching frozen view payloads with client/server seeding agreement",
    () => {
      assertSupportedHelperSeedingAgreement("supported-helper-src-module");
    },
    integrationTestTimeoutMs
  );

  it(
    "supported-helper-lib-source-dir emits matching frozen view payloads with client/server seeding agreement",
    () => {
      assertSupportedHelperSeedingAgreement("supported-helper-lib-source-dir");
    },
    integrationTestTimeoutMs
  );

  it(
    "mixed-supported-and-unsupported-lib still adopts supported direct freeze call in default mode",
    () => {
      assertMixedSupportedAndUnsupportedBehavior(
        "mixed-supported-and-unsupported-lib"
      );
    },
    integrationTestTimeoutMs
  );

  it(
    "mixed-supported-helper-unrelated-unsupported-lib still adopts supported helper",
    () => {
      assertSupportedHelperAdoptionWithUnrelatedUnsupported(
        "mixed-supported-helper-unrelated-unsupported-lib"
      );
    },
    integrationTestTimeoutMs
  );

  it(
    "direct-repeated-freeze-route de-optimizes direct repeated freeze callsites",
    () => {
      assertDirectRepeatedFreezeDeOptimized("direct-repeated-freeze-route");
    },
    integrationTestTimeoutMs
  );

  it(
    "supported-route-local-helper-two-sites seeds route-local helper calls and keeps client/server payloads in sync",
    () => {
      assertRouteLocalHelperSeedingAgreement(
        "supported-route-local-helper-two-sites"
      );
    },
    integrationTestTimeoutMs
  );

  it(
    "supported-shared-local-helper-two-sites seeds shared-local helper calls and keeps client/server payloads in sync",
    () => {
      assertSharedLocalHelperSeedingAgreement(
        "supported-shared-local-helper-two-sites"
      );
    },
    integrationTestTimeoutMs
  );

  it(
    "matrix-route-local-helper-mixed-static-and-map captures fallback behavior for mixed callsite shapes",
    () => {
      assertRouteLocalMixedCallsiteFallback(
        "matrix-route-local-helper-mixed-static-and-map"
      );
    },
    integrationTestTimeoutMs
  );

  it(
    "matrix-shared-route-unsupported-helper-importer-fallback keeps shared/route helper callsites de-optimized",
    () => {
      assertSharedAndRouteUnsupportedImporterFallback(
        "matrix-shared-route-unsupported-helper-importer-fallback"
      );
    },
    integrationTestTimeoutMs
  );
});
