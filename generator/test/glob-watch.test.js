import { describe, it, expect } from "vitest";
import {
  absoluteGlobPattern,
  globWatchEntry,
  parseWatchEntry,
  matchesAnyGlob,
  globWatcherIgnores,
} from "../src/glob-watch.js";

const file = { isFile: () => true, isDirectory: () => false };
const directory = { isFile: () => false, isDirectory: () => true };

describe("globWatchEntry and parseWatchEntry", () => {
  it("gives a glob's absolute pattern and the directory to watch for it", () => {
    expect(parseWatchEntry(globWatchEntry("/project", "content/blog/*.md"))).toEqual({
      kind: "glob",
      pattern: "/project/content/blog/*.md",
      baseDirectory: "/project/content/blog",
    });
    expect(parseWatchEntry(globWatchEntry("/project/content", "**/index.md"))).toEqual({
      kind: "glob",
      pattern: "/project/content/**/index.md",
      baseDirectory: "/project/content",
    });
  });

  it("treats a path as a file, whatever characters are in it", () => {
    for (const file of [
      "/project/content/hello.md",
      "/project/content/[slug].md",
      "/project/content/notes (1)/*.md",
      "/project/{a,b}/hello.md",
    ]) {
      expect(parseWatchEntry(file), file).toEqual({ kind: "file", path: file });
    }
  });

  it("takes the directory a glob runs in literally, whatever characters are in it", () => {
    const directory = "/home/me/my {old,new} project (1)/posts [2024]";
    const entry = parseWatchEntry(globWatchEntry(directory, "drafts/*.md"));

    expect(entry.kind).toBe("glob");
    expect(entry.baseDirectory).toBe(`${directory}/drafts`);
    const patterns = new Set([entry.pattern]);
    expect(matchesAnyGlob(patterns, `${directory}/drafts/a.md`)).toBe(true);
    expect(matchesAnyGlob(patterns, `${directory}/drafts/a.txt`)).toBe(false);
    // Not what the directory's name would match if it were read as a pattern.
    expect(
      matchesAnyGlob(patterns, "/home/me/my old project (1)/posts 2/drafts/a.md")
    ).toBe(false);
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
