/**
 * Watching the glob patterns that a page's BackendTasks ran, so the dev
 * server can reload the page's data when a matching file is added or removed.
 *
 * chokidar (version 4 and later) only watches plain files and directories,
 * not glob patterns. So for a pattern we watch the directory that all of its
 * matches are inside, and use these helpers to pick out the paths that match.
 */

import mm from "micromatch";

/**
 * Directories that are full of generated or installed files. A pattern like
 * "**\/*.md" would otherwise make us watch all of them.
 */
const noisyDirectories = new Set([
  "node_modules",
  "elm-stuff",
  ".elm-pages",
  ".git",
  "dist",
]);

const globEntryPrefix = "glob:";

/**
 * What the code that runs a glob reports, so the dev server can watch it.
 *
 * Files to watch are reported as their absolute path. A glob is reported as
 * this instead, so the two cannot be mixed up: a file's name can have
 * characters that mean something in a pattern, like "[slug].md".
 *
 * @param {string} directory - the absolute path of the directory the glob runs in
 * @param {string} pattern
 * @returns {string}
 */
export function globWatchEntry(directory, pattern) {
  return globEntryPrefix + JSON.stringify([directory, pattern]);
}

/**
 * @param {string} entry - a file's absolute path, or what `globWatchEntry` returns
 * @returns {{ kind: "file", path: string } | { kind: "glob", pattern: string, baseDirectory: string }}
 *   For a glob: its absolute pattern (see `absoluteGlobPattern`), and the
 *   directory that everything it matches is inside, which is the directory
 *   to watch.
 */
export function parseWatchEntry(entry) {
  if (!entry.startsWith(globEntryPrefix)) {
    return { kind: "file", path: entry };
  }
  const [directory, pattern] = JSON.parse(entry.slice(globEntryPrefix.length));
  // The part of the pattern before its first wildcard.
  const patternBase = mm.scan(pattern).base;
  return {
    kind: "glob",
    pattern: absoluteGlobPattern(directory, pattern),
    baseDirectory: [withoutTrailingSlash(directory), patternBase]
      .filter((part) => part !== "" && part !== ".")
      .join("/"),
  };
}

/**
 * A glob pattern runs in some directory (the project's, or another one with
 * `BackendTask.inDir`). This gives the pattern for the same files as absolute
 * paths, so it means the same thing wherever it is used.
 *
 * @param {string} directory - the absolute path of the directory the glob runs in
 * @param {string} pattern
 * @returns {string}
 */
export function absoluteGlobPattern(directory, pattern) {
  // The directory is a real path, not a pattern, so characters in it that
  // mean something in a pattern are escaped.
  const literalDirectory = withoutTrailingSlash(directory).replace(
    /[*?[\]{}()!+@|]/g,
    "\\$&"
  );
  return `${literalDirectory}/${pattern}`;
}

/**
 * @param {Iterable<string>} patterns - absolute, see `absoluteGlobPattern`
 * @param {string} absolutePath
 * @returns {boolean}
 */
export function matchesAnyGlob(patterns, absolutePath) {
  // A glob can be run with the `dot` option. Matching dotfiles for a pattern
  // that was run without it only means an extra data reload.
  return mm.isMatch(withForwardSlashes(absolutePath), [...patterns], {
    dot: true,
  });
}

/**
 * For chokidar's `ignored` option: should the watcher skip this path?
 *
 * @param {Iterable<string>} patterns - absolute, see `absoluteGlobPattern`
 * @param {string} projectDirectory - absolute
 * @param {string} absolutePath
 * @param {{ isFile(): boolean } | undefined} stats - chokidar does not always know them
 * @returns {boolean}
 */
export function globWatcherIgnores(
  patterns,
  projectDirectory,
  absolutePath,
  stats
) {
  // Only the part of the path inside the project counts here: the project
  // itself may well be in a directory called "dist".
  const insideProject = withForwardSlashes(absolutePath).slice(
    withForwardSlashes(projectDirectory).length
  );
  if (insideProject.split("/").some((part) => noisyDirectories.has(part))) {
    return true;
  }
  return Boolean(stats?.isFile()) && !matchesAnyGlob(patterns, absolutePath);
}

/** @param {string} directory */
function withoutTrailingSlash(directory) {
  return withForwardSlashes(directory).replace(/\/+$/, "");
}

/** @param {string} somePath */
function withForwardSlashes(somePath) {
  return somePath.replace(/\\/g, "/");
}
