module BuildError exposing (..)

import TerminalText


type alias BuildError =
    { message : List TerminalText.Text
    }
