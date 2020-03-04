module Pages.Http exposing (..)

import Http


type Error
    = BadUrl String
    | Timeout
    | NetworkError
    | BadStatus Http.Metadata String


expectString : (Result Error String -> msg) -> Http.Expect msg
expectString toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.BadUrl_ url ->
                    Err (BadUrl url)

                Http.Timeout_ ->
                    Err Timeout

                Http.NetworkError_ ->
                    Err NetworkError

                Http.BadStatus_ metadata body ->
                    Err (BadStatus metadata body)

                Http.GoodStatus_ metadata body ->
                    Ok body
