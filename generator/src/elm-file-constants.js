function elmPagesUiFile() {
  return `port module Pages exposing (builtAt, reloadData)

import Time
import Json.Decode
import Json.Encode


builtAt : Time.Posix
builtAt =
    Time.millisToPosix ${Math.round(global.builtAt.getTime())}


reloadData : { body : ( String, String ) } -> Cmd msg
reloadData options =
    elmPagesReloadData
        (Json.Encode.object
            [ ( "content-type", options.body |> Tuple.first |> Json.Encode.string )
            , ( "body", options.body |> Tuple.second |> Json.Encode.string )
            ]
        )


port elmPagesReloadData : Json.Decode.Value -> Cmd msg
`;
}

function elmPagesCliFile() {
  return elmPagesUiFile();
}
module.exports = { elmPagesUiFile, elmPagesCliFile };
