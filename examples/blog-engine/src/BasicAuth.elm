module BasicAuth exposing (withBasicAuth)

import BackendTask exposing (BackendTask)
import Base64
import Server.Request as Request exposing (Request)
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
    ({ username : String, password : String } -> BackendTask error Bool)
    -> BackendTask error (Response data errorPage)
    -> Request
    -> BackendTask error (Response data errorPage)
withBasicAuth checkAuth successResponse request =
    case request |> Request.header "authorization" |> Maybe.andThen parseAuth of
        Just userPass ->
            checkAuth userPass
                |> BackendTask.andThen
                    (\authSucceeded ->
                        if authSucceeded then
                            successResponse

                        else
                            requireBasicAuth |> BackendTask.succeed
                    )

        Nothing ->
            requireBasicAuth
                |> BackendTask.succeed


requireBasicAuth : Response data errorPage
requireBasicAuth =
    Response.emptyBody
        |> Response.withStatusCode 401
        |> Response.mapError never
        |> Response.withHeader "WWW-Authenticate" "Basic"
