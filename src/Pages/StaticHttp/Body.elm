module Pages.StaticHttp.Body exposing (Body, empty, string)

import Pages.Internal.StaticHttpBody exposing (Body(..))


empty : Body
empty =
    EmptyBody


string : String -> Body
string content =
    StringBody content


type alias Body =
    Pages.Internal.StaticHttpBody.Body
