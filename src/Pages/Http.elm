module Pages.Http exposing (Error(..))

import Http


type Error
    = BadUrl String
    | Timeout
    | NetworkError
    | BadStatus Http.Metadata String
