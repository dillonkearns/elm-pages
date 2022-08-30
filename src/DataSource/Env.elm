module DataSource.Env exposing (get, expect)

{-|

@docs get, expect

-}

import DataSource exposing (DataSource)
import DataSource.Http
import DataSource.Internal.Request
import Json.Decode as Decode
import Json.Encode as Encode


{-| -}
get : String -> DataSource error (Maybe String)
get envVariableName =
    DataSource.Internal.Request.request
        { name = "env"
        , body = DataSource.Http.jsonBody (Encode.string envVariableName)
        , expect =
            DataSource.Http.expectJson
                (Decode.nullable Decode.string)
        }


{-| -}
expect : String -> DataSource error String



-- TODO pull up error explicitly


expect envVariableName =
    envVariableName
        |> get
        |> DataSource.andThen
            (\maybeValue ->
                maybeValue
                    |> Result.fromMaybe ("DataSource.Env.expect was expecting a variable `" ++ envVariableName ++ "` but couldn't find a variable with that name.")
                    |> DataSource.fromResult
            )
