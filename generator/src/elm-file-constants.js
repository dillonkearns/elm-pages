function elmPagesUiFile() {
  return `port module Pages exposing (builtAt, reloadData)

import Time


builtAt : Time.Posix
builtAt =
    Time.millisToPosix ${Math.round(global.builtAt.getTime())}

reloadData : Cmd msg
reloadData =
    elmPagesReloadData ()

port elmPagesReloadData : () -> Cmd msg
`;
}

function elmPagesCliFile() {
  return elmPagesUiFile();
}
module.exports = { elmPagesUiFile, elmPagesCliFile };
