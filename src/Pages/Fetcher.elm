module Pages.Fetcher exposing (Fetcher(..), FetcherInfo, submit, map)

{-|

@docs Fetcher, FetcherInfo, submit, map

-}

import Bytes exposing (Bytes)
import Bytes.Decode
import Http


{-| -}
type Fetcher decoded
    = Fetcher (FetcherInfo decoded)


{-| -}
type alias FetcherInfo decoded =
    { decoder : Result Http.Error Bytes -> decoded
    , fields : List ( String, String )
    , headers : List ( String, String )
    , url : Maybe String
    }


{-| -}
submit :
    Bytes.Decode.Decoder decoded
    -> { fields : List ( String, String ), headers : List ( String, String ) }
    -> Fetcher (Result Http.Error decoded)
submit byteDecoder options =
    Fetcher
        { decoder =
            \bytesResult ->
                bytesResult
                    |> Result.andThen
                        (\okBytes ->
                            okBytes
                                |> Bytes.Decode.decode byteDecoder
                                |> Result.fromMaybe (Http.BadBody "Couldn't decode bytes.")
                        )
        , fields = options.fields
        , headers = ( "elm-pages-action-only", "true" ) :: options.headers
        , url = Nothing
        }


{-| -}
map : (a -> b) -> Fetcher a -> Fetcher b
map mapFn (Fetcher fetcher) =
    Fetcher
        { decoder = fetcher.decoder >> mapFn
        , fields = fetcher.fields
        , headers = fetcher.headers
        , url = fetcher.url
        }
