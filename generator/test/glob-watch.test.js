import { describe, it, expect } from "vitest";
import {
  absoluteGlobPattern,
  isGlobPattern,
  globBaseDirectory,
  matchesAnyGlob,
  globWatcherIgnores,
} from "../src/glob-watch.js";

const file = { isFile: () => true, isDirectory: () => false };
const directory = { isFile: () => false, isDirectory: () => true };

describe("isGlobPattern", () => {
  it("is false for a plain file path", () => {
    expect(isGlobPattern("content/blog/hello.md")).toBe(false);
  });

  it("is true for a pattern with a wildcard", () => {
    expect(isGlobPattern("content/blog/*.md")).toBe(true);
    expect(isGlobPattern("content/**/*.md")).toBe(true);
    expect(isGlobPattern("content/{a,b}.md")).toBe(true);
  });
});

describe("globBaseDirectory", () => {
  it("is the part of the pattern before the first wildcard", () => {
    expect(globBaseDirectory("content/blog/*.md")).toBe("content/blog");
    expect(globBaseDirectory("content/**/index.md")).toBe("content");
  });

  it("is the current directory when the pattern starts with a wildcard", () => {
    expect(globBaseDirectory("*.md")).toBe(".");
    expect(globBaseDirectory("**/*.md")).toBe(".");
  });
});

describe("absoluteGlobPattern", () => {
  it("puts the directory the glob runs in before the pattern", () => {
    expect(absoluteGlobPattern("/project", "content/*.md")).toBe(
      "/project/content/*.md"
    );
    expect(absoluteGlobPattern("/project/content/blog", "*.md")).toBe(
      "/project/content/blog/*.md"
    );
    expect(absoluteGlobPattern("/project", "**/*.md")).toBe(
      "/project/**/*.md"
    );
  });

  it("uses forward slashes, as glob patterns do, for a Windows directory", () => {
    expect(absoluteGlobPattern("C:\\project\\content", "*.md")).toBe(
      "C:/project/content/*.md"
    );
  });
});

describe("matchesAnyGlob", () => {
  it("matches a path against each pattern", () => {
    const patterns = new Set([
      "/project/content/blog/*.md",
      "/elsewhere/data/**/*.json",
    ]);
    expect(matchesAnyGlob(patterns, "/project/content/blog/new.md")).toBe(true);
    expect(matchesAnyGlob(patterns, "/elsewhere/data/a/b/c.json")).toBe(true);
    expect(matchesAnyGlob(patterns, "/project/content/blog/draft.txt")).toBe(
      false
    );
    expect(matchesAnyGlob(patterns, "/project/content/other/new.md")).toBe(
      false
    );
    expect(matchesAnyGlob(patterns, "/project/data/c.json")).toBe(false);
  });

  it("matches dotfiles, since a glob can be run with the dot option", () => {
    expect(
      matchesAnyGlob(new Set(["/project/content/*"]), "/project/content/.hidden")
    ).toBe(true);
  });
});

describe("globWatcherIgnores", () => {
  const patterns = new Set(["/project/**/*.md"]);
  /** @param {string} somePath @param {any} stats */
  const ignores = (somePath, stats) =>
    globWatcherIgnores(patterns, "/project", somePath, stats);

  it("keeps files that match a pattern", () => {
    expect(ignores("/project/content/post.md", file)).toBe(false);
  });

  it("ignores files that match no pattern", () => {
    expect(ignores("/project/content/post.txt", file)).toBe(true);
  });

  it("keeps directories, since matching files can be inside them", () => {
    expect(ignores("/project/content", directory)).toBe(false);
    expect(ignores("/project", directory)).toBe(false);
  });

  it("keeps a path when it is not known yet whether it is a file", () => {
    expect(ignores("/project/content", undefined)).toBe(false);
  });

  it("ignores directories of generated and installed files", () => {
    for (const noisy of [
      "/project/node_modules",
      "/project/node_modules/some-package/README.md",
      "/project/elm-stuff/notes.md",
      "/project/.elm-pages/notes.md",
      "/project/.git/notes.md",
      "/project/dist/notes.md",
      "/project/nested/node_modules/some-package/README.md",
    ]) {
      expect(ignores(noisy, undefined), noisy).toBe(true);
    }
  });

  it("does not mind what the directories above the project are called", () => {
    expect(
      globWatcherIgnores(
        new Set(["/home/dist/project/content/*.md"]),
        "/home/dist/project",
        "/home/dist/project/content/post.md",
        file
      )
    ).toBe(false);
  });
});
