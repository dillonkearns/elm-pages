module Pages.StaticHttpRequest exposing (Request(..))

import Head
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder)
import Pages.PagePath exposing (PagePath)


type Request
    = Request { url : String }
