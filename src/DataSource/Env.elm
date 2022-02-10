module DataSource.Env exposing (get, expect)

{-|

@docs get, expect

-}

import DataSource exposing (DataSource)
import DataSource.Http
import Json.Decode as Decode
import Json.Encode as Encode


{-| -}
get : String -> DataSource (Maybe String)
get envVariableName =
    DataSource.Http.request
        { url = "elm-pages-internal://env"
        , method = "GET"
        , headers = []
        , body = DataSource.Http.jsonBody (Encode.string envVariableName)
        }
        (DataSource.Http.expectJson
            (Decode.nullable Decode.string)
        )


{-| -}
expect : String -> DataSource String
expect envVariableName =
    envVariableName
        |> get
        |> DataSource.andThen
            (\maybeValue ->
                maybeValue
                    |> Result.fromMaybe ("DataSource.Env.expect was expecting a variable `" ++ envVariableName ++ "` but couldn't find a variable with that name.")
                    |> DataSource.fromResult
            )
