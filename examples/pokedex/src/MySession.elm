module MySession exposing (..)

import BackendTask exposing (BackendTask)
import BackendTask.Env as Env
import Codec
import Exception exposing (Throwable)
import Route
import Server.Request exposing (Parser)
import Server.Response exposing (Response)
import Server.Session as Session
import Server.SetCookie as SetCookie


cookieOptions : SetCookie.Options
cookieOptions =
    SetCookie.initOptions
        |> SetCookie.withPath "/"
        |> SetCookie.withSameSite SetCookie.Lax


withSession :
    (request -> Result Session.NotLoadedReason Session.Session -> BackendTask Throwable ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (BackendTask Throwable (Response data errorPage))
withSession =
    Session.withSession
        { name = "mysession"
        , secrets = secrets
        , options = cookieOptions
        }


withSessionOrRedirect :
    (request -> Session.Session -> BackendTask Throwable ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (BackendTask Throwable (Response data errorPage))
withSessionOrRedirect toRequest handler =
    Session.withSession
        { name = "mysession"
        , secrets = secrets
        , options = cookieOptions
        }
        (\request sessionResult ->
            sessionResult
                |> Result.map (toRequest request)
                |> Result.withDefault
                    (BackendTask.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
                        )
                    )
        )
        handler


secrets : BackendTask Throwable (List String)
secrets =
    Env.expect "SESSION_SECRET"
        |> BackendTask.throw
        |> BackendTask.map List.singleton


expectSessionOrRedirect :
    (request -> Session.Session -> BackendTask Throwable ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (BackendTask Throwable (Response data errorPage))
expectSessionOrRedirect toRequest handler =
    Session.withSession
        { name = "mysession"
        , secrets = secrets
        , options = cookieOptions
        }
        (\request sessionResult ->
            sessionResult
                |> Result.map (toRequest request)
                |> Result.withDefault
                    (BackendTask.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
                        )
                    )
        )
        handler


schema =
    { name = ( "name", Codec.string )
    , message = ( "message", Codec.string )
    , user =
        ( "user"
        , Codec.object User
            |> Codec.field "id" .id Codec.int
            |> Codec.buildObject
        )
    }


type alias User =
    { id : Int
    }
