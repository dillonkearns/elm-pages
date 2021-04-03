module PagesHttp exposing (..)

import Http exposing (Response(..))
import Pages.Http exposing (..)
import SimulatedEffect.Http


expectString : (Result Error String -> msg) -> SimulatedEffect.Http.Expect msg
expectString toMsg =
    SimulatedEffect.Http.expectStringResponse toMsg <|
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

                GoodStatus_ _ body ->
                    Ok body
