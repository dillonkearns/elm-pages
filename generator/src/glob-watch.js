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

/**
 * @param {string} pattern
 * @returns {boolean}
 */
export function isGlobPattern(pattern) {
  return mm.scan(pattern).isGlob;
}

/**
 * The directory that everything the pattern matches is inside: the part of
 * the pattern before its first wildcard.
 *
 * @param {string} pattern
 * @returns {string}
 */
export function globBaseDirectory(pattern) {
  return mm.scan(pattern).base || ".";
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
  return `${withForwardSlashes(directory).replace(/\/+$/, "")}/${pattern}`;
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

/** @param {string} somePath */
function withForwardSlashes(somePath) {
  return somePath.replace(/\\/g, "/");
}
