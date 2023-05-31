module String.Extra exposing (escape)


escape : String -> String
escape s =
    "\"" ++ s ++ "\""
