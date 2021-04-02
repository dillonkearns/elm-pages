module PagesHttp exposing (..)

import Http exposing (Response(..))
import Pages.Http exposing (..)
import SimulatedEffect.Http as Http


expectString : (Result Pages.Http.Error String -> msg) -> Http.Expect msg
expectString toMsg =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                BadUrl_ url ->
                    Err (BadUrl url)

                Timeout_ ->
                    Err Timeout

                NetworkError_ ->
                    Err NetworkError

                BadStatus_ metadata body ->
                    Err (BadStatus metadata body)

                GoodStatus_ metadata body ->
                    Ok body
