module Path exposing (..)

import Pages.Internal.String as String


join : String -> String -> String
join base path =
    String.chopEnd "/" base ++ "/" ++ String.chopStart "/" path
