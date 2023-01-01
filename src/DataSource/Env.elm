module DataSource.Env exposing
    ( get, expect
    , Error(..)
    )

{-| Because DataSource's in `elm-pages` never run in the browser (see [the DataSource docs](DataSource)), you can access environment variables securely. As long as the environment variable isn't sent
down into the final `Data` value, it won't end up in the client!

    import DataSource exposing (DataSource)
    import DataSource.Env

    type alias EnvVariables =
        { sendGridKey : String
        , siteUrl : String
        }

    sendEmail : Email -> DataSource ()
    sendEmail email =
        DataSource.map2 EnvVariables
            (DataSource.Env.expect "SEND_GRID_KEY")
            (DataSource.Env.get "BASE_URL"
                |> DataSource.map (Maybe.withDefault "http://localhost:1234")
            )
            |> DataSource.andThen (sendEmailDataSource email)

    sendEmailDataSource : Email -> EnvVariables -> DataSource ()
    sendEmailDataSource email envVariables =
        Debug.todo "Not defined here"

@docs get, expect


## Errors

@docs Error

-}

import DataSource exposing (DataSource)
import DataSource.Http
import DataSource.Internal.Request
import Exception exposing (Catchable)
import Json.Decode as Decode
import Json.Encode as Encode
import TerminalText


{-| -}
type Error
    = MissingEnvVariable String


{-| Get an environment variable, or Nothing if there is no environment variable matching that name.
-}
get : String -> DataSource error (Maybe String)
get envVariableName =
    DataSource.Internal.Request.request
        { name = "env"
        , body = DataSource.Http.jsonBody (Encode.string envVariableName)
        , expect =
            DataSource.Http.expectJson
                (Decode.nullable Decode.string)
        }
        |> DataSource.onError (\_ -> DataSource.succeed Nothing)


{-| Get an environment variable, or a DataSource failure if there is no environment variable matching that name.
-}
expect : String -> DataSource (Catchable Error) String
expect envVariableName =
    envVariableName
        |> get
        |> DataSource.andThen
            (\maybeValue ->
                maybeValue
                    |> Result.fromMaybe
                        (Exception.Catchable (MissingEnvVariable envVariableName)
                            { title = "Missing Env Variable"
                            , body =
                                [ TerminalText.text "DataSource.Env.expect was expecting a variable `"
                                , TerminalText.yellow envVariableName
                                , TerminalText.text "` but couldn't find a variable with that name."
                                ]
                            }
                        )
                    |> DataSource.fromResult
            )
