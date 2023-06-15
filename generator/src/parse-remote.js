export function parse(input) {
  const match = parseGithubUrl(input) || parseRemotePath(input);

  if (match) {
    const g = match.groups;
    return {
      remote: `https://github.com/${g.owner}/${g.repo}.git`,
      filePath: g.filePath || null,
      branch: g.branch || null,
      owner: g.owner,
      repo: g.repo,
    };
  } else {
    return null;
  }
}

/**
 * @param {string} input
 */
function parseGithubUrl(input) {
  return input.match(
    /https?:\/\/github.com\/(?<owner>[^/]+)\/(?<repo>[^/]+)(\/(blob|tree)\/(?<branch>[^/]+)(\/(?<filePath>.*)))?(#?.*)$/
  );
}

/**
 * @param {string} possibleRemotePath
 */
function parseRemotePath(possibleRemotePath) {
  // "github:user/repo:script/src/Hello.elm",
  const githubRegex =
    /github:(?<owner>[^\/]+)\/(?<repo>[^\/]+):(?<filePath>.*)$/;
  return possibleRemotePath.match(githubRegex);
}
