module MySession exposing (..)

import Codec
import DataSource exposing (DataSource)
import DataSource.Env as Env
import Route
import Server.Request exposing (Parser)
import Server.Response as Response exposing (Response)
import Server.Session as Session
import Server.SetCookie as SetCookie


cookieOptions : SetCookie.Options
cookieOptions =
    SetCookie.initOptions
        |> SetCookie.withPath "/"
        |> SetCookie.withSameSite SetCookie.Lax


withSession :
    (request -> Result Session.NotLoadedReason Session.Session -> DataSource ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (DataSource (Response data errorPage))
withSession =
    Session.withSession
        { name = "mysession"
        , secrets = secrets
        , options = cookieOptions
        }


withSessionOrRedirect :
    (request -> Session.Session -> DataSource ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (DataSource (Response data errorPage))
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
                    (DataSource.succeed
                        ( Session.empty
                        , Route.redirectTo Route.Login
                        )
                    )
        )
        handler


secrets : DataSource (List String)
secrets =
    Env.expect "SESSION_SECRET" |> DataSource.map List.singleton


expectSessionOrRedirect :
    (request -> Session.Session -> DataSource ( Session.Session, Response data errorPage ))
    -> Parser request
    -> Parser (DataSource (Response data errorPage))
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
                    (DataSource.succeed
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
