module MySession exposing (..)

import Codec
import BackendTask exposing (BackendTask)
import BackendTask.Env as Env
import Route
import Server.Request exposing (Parser)
import Server.Response as Response exposing (Response)
import Server.Session as Session


withSession :
    Parser request
    -> (request -> Result () (Maybe Session.Session) -> BackendTask ( Session.Session, Response data errorPage ))
    -> Parser (BackendTask (Response data errorPage))
withSession =
    Session.withSession
        { name = "mysession"
        , secrets = Env.expect "SESSION_SECRET" |> BackendTask.map List.singleton
        , sameSite = "lax"
        }


withSessionOrRedirect :
    Parser request
    -> (request -> Maybe Session.Session -> BackendTask ( Session.Session, Response data errorPage ))
    -> Parser (BackendTask (Response data errorPage))
withSessionOrRedirect handler toRequest =
    Session.withSession
        { name = "mysession"
        , secrets = Env.expect "SESSION_SECRET" |> BackendTask.map List.singleton
        , sameSite = "lax"
        }
        handler
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


expectSessionOrRedirect :
    (request -> Session.Session -> BackendTask ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (BackendTask (Response data errorPage))
expectSessionOrRedirect toRequest handler =
    Session.withSession
        { name = "mysession"
        , secrets = Env.expect "SESSION_SECRET" |> BackendTask.map List.singleton
        , sameSite = "lax"
        }
        handler
        (\request sessionResult ->
            sessionResult
                |> Result.map (Maybe.map (toRequest request))
                |> Result.withDefault Nothing
                |> Maybe.withDefault
                    (BackendTask.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
                        )
                    )
        )


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
