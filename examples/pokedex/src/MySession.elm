module MySession exposing (..)

import BackendTask exposing (BackendTask)
import BackendTask.Env as Env
import Codec
import FatalError exposing (FatalError)
import Route
import Server.Request exposing (Request)
import Server.Response exposing (Response)
import Server.Session as Session


withSession :
    (Result Session.NotLoadedReason Session.Session -> BackendTask FatalError ( Session.Session, Response data errorPage ))
    -> Request
    -> BackendTask FatalError (Response data errorPage)
withSession =
    Session.withSessionResult
        { name = "mysession"
        , secrets = secrets
        , options = Nothing
        }


withSessionOrRedirect :
    (Session.Session -> BackendTask FatalError ( Session.Session, Response data errorPage ))
    -> Request
    -> BackendTask FatalError (Response data errorPage)
withSessionOrRedirect toRequest handler =
    Session.withSessionResult
        { name = "mysession"
        , secrets = secrets
        , options = Nothing
        }
        (\sessionResult ->
            sessionResult
                |> Result.map toRequest
                |> Result.withDefault
                    (BackendTask.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
                        )
                    )
        )
        handler


secrets : BackendTask FatalError (List String)
secrets =
    Env.expect "SESSION_SECRET"
        |> BackendTask.allowFatal
        |> BackendTask.map List.singleton


expectSessionOrRedirect :
    (Session.Session -> BackendTask FatalError ( Session.Session, Response data errorPage ))
    -> Request
    -> BackendTask FatalError (Response data errorPage)
expectSessionOrRedirect toRequest request =
    Session.withSessionResult
        { name = "mysession"
        , secrets = secrets
        , options = Nothing
        }
        (\sessionResult ->
            sessionResult
                |> Result.map toRequest
                |> Result.withDefault
                    (BackendTask.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
                        )
                    )
        )
        request


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
