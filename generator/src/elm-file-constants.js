const exposingList = "(internals, builtAt)";

function elmPagesUiFile() {
  return `port module Pages exposing ${exposingList}

import Color exposing (Color)
import Pages.Internal
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import Url.Parser as Url exposing ((</>), s)
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Directory as Directory exposing (Directory)
import Time


builtAt : Time.Posix
builtAt =
    Time.millisToPosix ${Math.round(global.builtAt.getTime())}


port toJsPort : Json.Encode.Value -> Cmd msg

port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg


internals : Pages.Internal.Internal ()
internals =
    { applicationType = Pages.Internal.Browser
    , toJsPort = toJsPort
    , fromJsPort = fromJsPort identity
    , pathKey = ()
    }
`;
}

function elmPagesCliFile() {
  return `port module Pages exposing ${exposingList}

import Color exposing (Color)
import Pages.Internal
import Head
import Html exposing (Html)
import Json.Decode
import Json.Encode
import Pages.Manifest exposing (DisplayMode, Orientation)
import Pages.Manifest.Category as Category exposing (Category)
import Url.Parser as Url exposing ((</>), s)
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Directory as Directory exposing (Directory)
import Time


builtAt : Time.Posix
builtAt =
    Time.millisToPosix ${Math.round(global.builtAt.getTime())}


port toJsPort : Json.Encode.Value -> Cmd msg


port fromJsPort : (Json.Decode.Value -> msg) -> Sub msg


internals : Pages.Internal.Internal ()
internals =
    { applicationType = Pages.Internal.Cli
    , toJsPort = toJsPort
    , fromJsPort = fromJsPort identity
    , pathKey = ()
    }
`;
}
module.exports = { elmPagesUiFile, elmPagesCliFile };
