module MySession exposing (..)

import BackendTask exposing (BackendTask)
import BackendTask.Env as Env
import Codec
import FatalError exposing (FatalError)
import Route
import Server.Request exposing (Parser)
import Server.Response exposing (Response)
import Server.Session as Session


withSession :
    (request -> Result Session.NotLoadedReason Session.Session -> BackendTask FatalError ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (BackendTask FatalError (Response data errorPage))
withSession =
    Session.withSessionResult
        { name = "mysession"
        , secrets = secrets
        , options = Nothing
        }


withSessionOrRedirect :
    (request -> Session.Session -> BackendTask FatalError ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (BackendTask FatalError (Response data errorPage))
withSessionOrRedirect toRequest handler =
    Session.withSessionResult
        { name = "mysession"
        , secrets = secrets
        , options = Nothing
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


secrets : BackendTask FatalError (List String)
secrets =
    Env.expect "SESSION_SECRET"
        |> BackendTask.allowFatal
        |> BackendTask.map List.singleton


expectSessionOrRedirect :
    (request -> Session.Session -> BackendTask FatalError ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (BackendTask FatalError (Response data errorPage))
expectSessionOrRedirect toRequest handler =
    Session.withSessionResult
        { name = "mysession"
        , secrets = secrets
        , options = Nothing
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
