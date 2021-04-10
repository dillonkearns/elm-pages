function elmPagesUiFile() {
  return `module Pages exposing (builtAt)

import Time


builtAt : Time.Posix
builtAt =
    Time.millisToPosix ${Math.round(global.builtAt.getTime())}
`;
}

function elmPagesCliFile() {
  return elmPagesUiFile();
}
module.exports = { elmPagesUiFile, elmPagesCliFile };
