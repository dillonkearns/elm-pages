function elmPagesUiFile() {
  return `module Pages exposing (builtAt)

import Time
import Json.Decode
import Json.Encode


builtAt : Time.Posix
builtAt =
    Time.millisToPosix ${Math.round(global.builtAt.getTime())}
`;
}

function elmPagesCliFile() {
  return elmPagesUiFile();
}
module.exports = { elmPagesUiFile, elmPagesCliFile };
