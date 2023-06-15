/**
 * @param {string} input
 */
export function parse(input) {
  const patterns = [
    /https?:\/\/github\.com\/(?<owner>[^/]+)\/(?<repo>[^/]+)(\/(blob|tree)\/(?<branch>[^/]+)(\/(?<filePath>.*)))?(#?.*)$/,
    /github:(?<owner>[^\/]+)\/(?<repo>[^\/]+):(?<filePath>.*)$/,
    /http(s)?:\/\/raw\.githubusercontent\.com\/(?<owner>[^\/]+)\/(?<repo>[^\/]+)\/(?<branch>[^\/]+)\/(?<filePath>.*)$/,
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
    const gistPatterns = [
      /https?:\/\/gist\.github.com\/(?<owner>[^\/]+)\/(?<repo>[^\/]+)(\/?#(?<filePath>.*))?$/,
      /https?:\/\/gist\.github.com\/(?<repo>[^\/]+)(\/?#(?<filePath>.*))?$/,
      /https?:\/\/gist\.githubusercontent\.com\/(?<owner>[^\/]+)\/(?<repo>[^\/]+)\/raw\/(?<sha>[^/]+)\/(?<filePath>.*)?$/,
    ];
    const gistMatch = gistPatterns
      .map((pattern) => input.match(pattern))
      .find((m) => m);
    if (gistMatch) {
      const g = gistMatch.groups;
      return {
        remote: `https://gist.github.com/${g.repo}.git`,
        filePath: g.filePath || "Main.elm",
        branch: null,
        owner: g.owner || "gist",
        repo: g.repo,
      };
    } else {
      return null;
    }
  }
}
