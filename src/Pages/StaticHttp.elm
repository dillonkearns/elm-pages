module Pages.StaticHttp exposing (Request, get, none)

import Pages.StaticHttpRequest exposing (Request(..))


get : String -> (String -> value) -> Request value
get url parser =
    Request
        { parser = parser
        , url = url
        }


none : Request ()
none =
    Request
        { parser = \_ -> ()
        , url = "TODO"
        }


type alias Request value =
    Pages.StaticHttpRequest.Request value
