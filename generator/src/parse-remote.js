/**
 * @param {string} input
 */
export function parse(input) {
  const patterns = [
    /https?:\/\/github.com\/(?<owner>[^/]+)\/(?<repo>[^/]+)(\/(blob|tree)\/(?<branch>[^/]+)(\/(?<filePath>.*)))?(#?.*)$/,
    /github:(?<owner>[^\/]+)\/(?<repo>[^\/]+):(?<filePath>.*)$/,
  ];
  const match = patterns.map((pattern) => input.match(pattern)).find((m) => m);

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
