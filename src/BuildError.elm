module BuildError exposing (..)

import TerminalText


type alias BuildError =
    { title : String
    , message : List TerminalText.Text
    }
