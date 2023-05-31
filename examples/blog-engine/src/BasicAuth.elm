module BasicAuth exposing (withBasicAuth)

import BackendTask exposing (BackendTask)
import Base64
import Server.Request as Request exposing (Parser)
import Server.Response as Response exposing (Response)


parseAuth : String -> Maybe { username : String, password : String }
parseAuth base64Auth =
    case
        base64Auth
            |> String.dropLeft 6
            |> Base64.toString
            |> Maybe.map (String.split ":")
    of
        Just [ username, password ] ->
            Just
                { username = username
                , password = password
                }

        _ ->
            Nothing


withBasicAuth :
    Parser requestData
    -> (requestData -> { username : String, password : String } -> BackendTask error Bool)
    -> (requestData -> BackendTask error (Response data errorPage))
    -> Parser (BackendTask error (Response data errorPage))
withBasicAuth userRequestParser checkAuth successResponse =
    Request.map2
        (\base64Auth userRequestData ->
            case base64Auth |> Maybe.andThen parseAuth of
                Just userPass ->
                    checkAuth userRequestData userPass
                        |> BackendTask.andThen
                            (\authSucceeded ->
                                if authSucceeded then
                                    successResponse userRequestData

                                else
                                    requireBasicAuth |> BackendTask.succeed
                            )

                Nothing ->
                    requireBasicAuth
                        |> BackendTask.succeed
        )
        (Request.optionalHeader "authorization")
        userRequestParser


requireBasicAuth : Response data errorPage
requireBasicAuth =
    Response.emptyBody
        |> Response.withStatusCode 401
        |> Response.mapError never
        |> Response.withHeader "WWW-Authenticate" "Basic"
