module Pages.StaticHttpRequest exposing (Request(..), parser)


type Request value
    = Request
        { parser : String -> value
        , url : String
        }


parser : Request value -> (String -> value)
parser (Request request) =
    request.parser
